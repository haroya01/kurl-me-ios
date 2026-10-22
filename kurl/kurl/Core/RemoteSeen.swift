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
}

@MainActor
final class RemoteSeenReporter {
    static let shared = RemoteSeenReporter()
    static let batchSize = 20
    static let queueLimit = 200

    private let send: @MainActor ([String]) async throws -> Void
    private let wait: @MainActor () async throws -> Void
    private var pending: [String] = []
    private var retrying: [String] = []
    private var known: Set<String> = []
    private var timer: Task<Void, Never>?

    init(
        send: @escaping @MainActor ([String]) async throws -> Void = FederationAPI.markSeen,
        wait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(10)) }
    ) {
        self.send = send
        self.wait = wait
    }

    var queued: Int { pending.count + retrying.count }

    func mark(_ uri: String) {
        guard queued < Self.queueLimit, known.insert(uri).inserted else { return }
        pending.append(uri)
        if pending.count >= Self.batchSize {
            flush()
        } else if timer == nil {
            timer = Task { [weak self, wait] in
                guard (try? await wait()) != nil, !Task.isCancelled else { return }
                self?.flush()
            }
        }
    }

    @discardableResult
    func flush() -> Task<Void, Never> {
        timer?.cancel()
        timer = nil
        let retried = retrying
        let batch = retrying + pending
        retrying = []
        pending = []
        guard !batch.isEmpty else { return Task {} }
        return Task {
            do {
                try await send(batch)
            } catch {
                settle(failed: batch, retried: Set(retried))
            }
        }
    }

    func flushBeforeSuspending() {
        guard queued > 0 else { return }
        let app = UIApplication.shared
        let assertion = app.beginBackgroundTask(withName: "remote-seen")
        let sending = flush()
        Task {
            await sending.value
            app.endBackgroundTask(assertion)
        }
    }

    private func settle(failed: [String], retried: Set<String>) {
        let again = failed.filter { !retried.contains($0) }
        let room = max(0, Self.queueLimit - queued)
        retrying += again.prefix(room)
        for uri in failed where retried.contains(uri) { known.remove(uri) }
        for uri in again.dropFirst(room) { known.remove(uri) }
    }
}

private struct RemoteSeenMark: ViewModifier {
    let uri: String?
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.5) { visible = $0 }
            .task(id: uri != nil && visible && scenePhase == .active) {
                guard let uri, visible, scenePhase == .active else { return }
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                RemoteSeenReporter.shared.mark(uri)
            }
    }
}

extension View {
    func marksRemoteSeen(_ uri: String?) -> some View {
        modifier(RemoteSeenMark(uri: uri))
    }

    func flushesRemoteSeen(while measuring: Bool) -> some View {
        onChange(of: measuring) { _, now in
            if !now { RemoteSeenReporter.shared.flush() }
        }
        .onDisappear { RemoteSeenReporter.shared.flush() }
    }
}
