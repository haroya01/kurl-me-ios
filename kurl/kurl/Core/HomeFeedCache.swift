import Foundation

@MainActor
final class HomeFeedCache {
    static let shared = HomeFeedCache(enabled: !Config.isUnitTestHost && !Config.useMocks)
    static let maxAge: TimeInterval = 24 * 60 * 60

    private let directory: URL
    private let enabled: Bool
    private let now: () -> Date
    private let io = DispatchQueue(label: "kurl.home-feed-cache", qos: .utility)
    private(set) var generation = 0

    init(
        directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home-feed", isDirectory: true),
        enabled: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.enabled = enabled
        self.now = now
    }

    struct Ticket {
        fileprivate let generation: Int
        fileprivate let signedIn: Bool
    }

    func ticket() -> Ticket {
        Ticket(generation: generation, signedIn: AuthStore.shared.isSignedIn)
    }

    func store(
        _ data: Data, batch: HomeFeedBatch, tab: HomeFeedTab, ticket: Ticket,
        withheld: @MainActor (HomeFeedItem) -> Bool = HomeFeedCache.withheld
    ) {
        guard enabled, ticket.generation == generation, ticket.signedIn == AuthStore.shared.isSignedIn else { return }
        let dropped = Set(batch.items.filter(withheld).map(\.id))
        guard let kept = Self.keepable(data, dropping: dropped) else { return }
        let url = file(tab, signedIn: ticket.signedIn)
        let directory = directory
        io.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? kept.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func withheld(_ item: HomeFeedItem) -> Bool {
        if item.roomId != nil { return true }
        switch item.kind {
        case .note(let note):
            return BlockStore.shared.isBlocked(note.author.username)
                || NoteFilterStore.shared.verdict(for: note, in: .home) != nil
        case .post(let post):
            return BlockStore.shared.isBlocked(post.author.username)
        case .remote(.kept(let note)):
            return BlockStore.shared.isBlocked(note.author.username)
                || NoteFilterStore.shared.verdict(for: note, in: .home) != nil
        case .remote(.trending(let note)):
            return BlockStore.shared.isBlocked(note.author.username)
        }
    }

    func read(_ tab: HomeFeedTab) async -> HomeFeedBatch? {
        guard enabled else { return nil }
        let url = file(tab, signedIn: AuthStore.shared.isSignedIn)
        let oldest = now().addingTimeInterval(-Self.maxAge)
        let generation = generation
        let data = await withCheckedContinuation { (done: CheckedContinuation<Data?, Never>) in
            io.async {
                guard let saved = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      saved >= oldest
                else { return done.resume(returning: nil) }
                done.resume(returning: try? Data(contentsOf: url))
            }
        }
        guard generation == self.generation, let data,
              let batch = try? JSONDecoder.blog.decode(HomeFeedBatch.self, from: data), !batch.items.isEmpty
        else { return nil }
        return batch
    }

    func wipe() {
        generation += 1
        let directory = directory
        io.async { try? FileManager.default.removeItem(at: directory) }
    }

    func settle() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in io.async { done.resume() } }
    }

    private func file(_ tab: HomeFeedTab, signedIn: Bool) -> URL {
        directory.appendingPathComponent("\(signedIn ? "member" : "guest")-\(tab.rawValue).json")
    }

    nonisolated static func keepable(_ data: Data, dropping dropped: Set<String>) -> Data? {
        guard var page = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = page["items"] as? [[String: Any]]
        else { return nil }
        page["items"] = items.filter { item in
            guard let kind = item["kind"] as? String,
                  let body = item[kind == "post" ? "post" : "note"] as? [String: Any],
                  let id = (body["id"] as? NSNumber)?.int64Value
            else { return false }
            return !dropped.contains("\(kind == "post" ? "post" : "note")-\(id)")
        }
        page["gap"] = nil
        return try? JSONSerialization.data(withJSONObject: page)
    }
}
