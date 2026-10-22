import SwiftUI

extension HomeFeedItem {
    var seenKey: String {
        switch kind {
        case .note(let note): "kurl:note:\(note.id)"
        case .post(let post): "kurl:post:\(post.id)"
        }
    }

    var authorID: Int64 {
        switch kind {
        case .note(let note): note.author.id
        case .post(let post): post.author.id
        }
    }
}

@MainActor
final class HomeSeenLog {
    static let shared = HomeSeenLog()
    static let storagePrefix = "homeSeenLog."
    static let keep: TimeInterval = 14 * 24 * 60 * 60
    static let limit = 3_000

    private let defaults: UserDefaults
    private let now: () -> Date
    private let viewer: @MainActor () -> Int64?
    private var storageKey: String
    private var seen: [String: Double]
    private var saving: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        viewer: @escaping @MainActor () -> Int64? = { AuthStore.shared.accountId }
    ) {
        self.defaults = defaults
        self.now = now
        self.viewer = viewer
        storageKey = Self.storageKey(for: viewer())
        seen = (defaults.dictionary(forKey: storageKey) as? [String: Double]) ?? [:]
    }

    static func storageKey(for account: Int64?) -> String {
        storagePrefix + (account.map { "user.\($0)" } ?? "device")
    }

    private func follow() {
        let current = Self.storageKey(for: viewer())
        guard current != storageKey else { return }
        save()
        storageKey = current
        seen = (defaults.dictionary(forKey: storageKey) as? [String: Double]) ?? [:]
    }

    func contains(_ key: String) -> Bool {
        follow()
        guard let at = seen[key] else { return false }
        return now().timeIntervalSince1970 - at < Self.keep
    }

    func record(_ key: String) {
        guard !contains(key) else { return }
        let stamp = now().timeIntervalSince1970
        seen[key] = stamp
        if seen.count > Self.limit {
            seen = seen.filter { stamp - $0.value < Self.keep }
            if seen.count > Self.limit {
                let oldest = seen.sorted { $0.value < $1.value }.prefix(seen.count - Self.limit).map(\.key)
                for key in oldest { seen[key] = nil }
            }
        }
        guard saving == nil else { return }
        saving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.save()
        }
    }

    func save() {
        saving?.cancel()
        saving = nil
        defaults.set(seen, forKey: storageKey)
    }

    func wipeAccounts() {
        saving?.cancel()
        saving = nil
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.storagePrefix + "user.") {
            defaults.removeObject(forKey: key)
        }
        if storageKey.hasPrefix(Self.storagePrefix + "user.") { seen = [:] }
    }
}

private struct HomeSeenMark: ViewModifier {
    let key: String?
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0) { visible = $0 }
            .onChange(of: visible && key != nil && scenePhase == .active, initial: true) { _, now in
                guard now, let key else { return }
                HomeSeenLog.shared.record(key)
                RemoteSeenReporter.shared.mark(key, feed: .forYou)
            }
    }
}

extension View {
    func marksHomeSeen(_ key: String?) -> some View {
        modifier(HomeSeenMark(key: key))
    }
}
