import SwiftUI
import UIKit

enum RemoteSeenDevice {
    static let header = "X-Kurl-Device"
    static let key = "remoteSeenDevice"

    static func id(_ defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: key), UUID(uuidString: saved) != nil { return saved }
        let made = UUID().uuidString.lowercased()
        defaults.set(made, forKey: key)
        return made
    }
}

extension RemoteStreamItem {
    var seenURI: String? {
        switch self {
        case .trending(let note): note.uri
        case .kept(let note): note.uri
        }
    }

    var key: String { seenURI ?? id }

    var keptID: Int64? {
        if case .kept(let note) = self { note.id } else { nil }
    }
}

struct RemoteDwell: Encodable, Hashable {
    let uri: String
    let ms: Int
}

struct RemoteSeenBatch: Encodable, Equatable {
    let uris: [String]
    let dwell: [RemoteDwell]?
    let feed: String
}

struct RemoteSeenTarget: Equatable {
    let uri: String
    let feed: RemoteStreamFeed
    var noteID: Int64?
    var marks = true
}

@MainActor
final class RemoteSeenReporter {
    static let shared = RemoteSeenReporter()
    static let batchSize = 20
    static let queueLimit = 200
    static let dwellLimit = 100
    static let dwellFloor = 1_000
    static let dwellCap = 600_000

    private struct Pile {
        var uris: [String] = []
        var dwell: [String: Int] = [:]

        var isEmpty: Bool { uris.isEmpty && dwell.isEmpty }
    }

    private let send: @MainActor (RemoteSeenBatch) async throws -> Void
    private let wait: @MainActor () async throws -> Void
    private var pending: [RemoteStreamFeed: Pile] = [:]
    private var retrying: [RemoteStreamFeed: Pile] = [:]
    private var known: Set<String> = []
    private var dwelt: [String: Int] = [:]
    private var opened: [Int64: (uri: String, feed: RemoteStreamFeed)] = [:]
    private var timer: Task<Void, Never>?

    init(
        send: @escaping @MainActor (RemoteSeenBatch) async throws -> Void = FederationAPI.markSeen,
        wait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(10)) }
    ) {
        self.send = send
        self.wait = wait
    }

    var queued: Int {
        pending.values.reduce(0) { $0 + $1.uris.count } + retrying.values.reduce(0) { $0 + $1.uris.count }
    }

    func mark(_ uri: String, feed: RemoteStreamFeed) {
        guard queued < Self.queueLimit, known.insert(uri).inserted else { return }
        pending[feed, default: Pile()].uris.append(uri)
        if pending.values.reduce(0, { $0 + $1.uris.count }) >= Self.batchSize {
            flush()
        } else {
            startTimer()
        }
    }

    func dwell(_ uri: String, ms: Int, feed: RemoteStreamFeed) {
        guard ms > 0 else { return }
        let total = min(Self.dwellCap, dwelt[uri, default: 0] + ms)
        dwelt[uri] = total
        guard total >= Self.dwellFloor else { return }
        let pile = pending[feed, default: Pile()]
        guard pile.dwell[uri] != nil || pile.dwell.count < Self.dwellLimit else { return }
        pending[feed, default: Pile()].dwell[uri] = total
        startTimer()
    }

    func remember(_ noteID: Int64, uri: String, feed: RemoteStreamFeed) {
        opened[noteID] = (uri, feed)
    }

    func dwell(note noteID: Int64, ms: Int) {
        guard let (uri, feed) = opened[noteID] else { return }
        dwell(uri, ms: ms, feed: feed)
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Task { [weak self, wait] in
            guard (try? await wait()) != nil, !Task.isCancelled else { return }
            self?.flush()
        }
    }

    @discardableResult
    func flush() -> Task<Void, Never> {
        timer?.cancel()
        timer = nil
        let batches = RemoteStreamFeed.allCases.compactMap { feed -> (RemoteStreamFeed, Pile, Pile)? in
            let before = retrying[feed] ?? Pile()
            var pile = before
            if let fresh = pending[feed] {
                pile.uris += fresh.uris
                pile.dwell.merge(fresh.dwell, uniquingKeysWith: max)
            }
            return pile.isEmpty ? nil : (feed, pile, before)
        }
        retrying = [:]
        pending = [:]
        guard !batches.isEmpty else { return Task {} }
        return Task {
            for (feed, pile, before) in batches {
                let dwell = pile.dwell.sorted { $0.key < $1.key }.map { RemoteDwell(uri: $0.key, ms: $0.value) }
                do {
                    try await send(RemoteSeenBatch(uris: pile.uris, dwell: dwell.isEmpty ? nil : dwell, feed: feed.rawValue))
                } catch {
                    settle(feed, failed: pile, retried: before)
                }
            }
        }
    }

    func flushBeforeSuspending() {
        guard queued > 0 || pending.values.contains(where: { !$0.dwell.isEmpty }) else { return }
        let app = UIApplication.shared
        let assertion = app.beginBackgroundTask(withName: "remote-seen")
        let sending = flush()
        Task {
            await sending.value
            app.endBackgroundTask(assertion)
        }
    }

    private func settle(_ feed: RemoteStreamFeed, failed: Pile, retried: Pile) {
        let retriedURIs = Set(retried.uris)
        let again = failed.uris.filter { !retriedURIs.contains($0) }
        let room = max(0, Self.queueLimit - queued)
        var pile = retrying[feed] ?? Pile()
        pile.uris += again.prefix(room)
        for uri in failed.uris where retriedURIs.contains(uri) { known.remove(uri) }
        for uri in again.dropFirst(room) { known.remove(uri) }
        for (uri, ms) in failed.dwell where retried.dwell[uri] == nil && pile.dwell.count < Self.dwellLimit {
            pile.dwell[uri] = max(pile.dwell[uri] ?? 0, ms)
        }
        retrying[feed] = pile
    }
}

private struct RemoteSeenMark: ViewModifier {
    let target: RemoteSeenTarget?
    @State private var visible = false
    @State private var counting: (target: RemoteSeenTarget, since: ContinuousClock.Instant)?
    @Environment(\.scenePhase) private var scenePhase

    private var marking: Bool { target?.marks == true && visible && scenePhase == .active }
    private var dwelling: Bool { target != nil && visible && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.5) { visible = $0 }
            .task(id: marking) {
                guard let target, marking else { return }
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                RemoteSeenReporter.shared.mark(target.uri, feed: target.feed)
            }
            .onChange(of: dwelling) { _, now in
                stop()
                if now { start() }
            }
            .onChange(of: target) { _, _ in
                stop()
                if dwelling { start() }
            }
            .onDisappear { stop() }
    }

    private func start() {
        guard let target else { return }
        if let noteID = target.noteID {
            RemoteSeenReporter.shared.remember(noteID, uri: target.uri, feed: target.feed)
        }
        counting = (target, .now)
    }

    private func stop() {
        guard let counting else { return }
        self.counting = nil
        RemoteSeenReporter.shared.dwell(
            counting.target.uri, ms: counting.since.duration(to: .now).milliseconds, feed: counting.target.feed)
    }
}

private struct RemoteNoteDwell: ViewModifier {
    let noteID: Int64
    @State private var shown = false
    @State private var since: ContinuousClock.Instant?
    @Environment(\.scenePhase) private var scenePhase

    private var dwelling: Bool { shown && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .onAppear { shown = true }
            .onDisappear { shown = false }
            .onChange(of: dwelling) { _, now in
                if let since {
                    self.since = nil
                    RemoteSeenReporter.shared.dwell(note: noteID, ms: since.duration(to: .now).milliseconds)
                }
                if now { since = .now }
            }
    }
}

private extension Duration {
    var milliseconds: Int {
        let parts = components
        return Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}

extension View {
    func marksRemoteSeen(_ target: RemoteSeenTarget?) -> some View {
        modifier(RemoteSeenMark(target: target))
    }

    func dwellsOnRemoteNote(_ noteID: Int64) -> some View {
        modifier(RemoteNoteDwell(noteID: noteID))
    }

    func flushesRemoteSeen(while measuring: Bool) -> some View {
        onChange(of: measuring) { _, now in
            if !now { RemoteSeenReporter.shared.flush() }
        }
        .onDisappear { RemoteSeenReporter.shared.flush() }
    }
}
