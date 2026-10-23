import Foundation

enum HomeFeedTab: String, CaseIterable, Identifiable, Hashable {
    case forYou = "for-you"
    case following
    case blog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .forYou: String(localized: "추천")
        case .following: String(localized: "팔로잉")
        case .blog: String(localized: "블로그")
        }
    }

    var symbol: String {
        switch self {
        case .forYou: "binoculars"
        case .following: "person.2"
        case .blog: "doc.text"
        }
    }

    var requiresAuth: Bool { self == .following }

    static let loadOnSelect: Set<HomeFeedTab> = [.following, .blog]

    var hidesSeen: Bool { self == .forYou }

    func query(_ rest: [String: String?]) -> [String: String?] {
        var query = rest
        query["tab"] = rawValue
        if hidesSeen { query["seen"] = "hide" }
        return query
    }

    var headers: [String: String] {
        hidesSeen ? [RemoteSeenDevice.header: RemoteSeenDevice.id()] : [:]
    }

    init?(stored: String) {
        switch stored {
        case "following": self = .following
        case "blog": self = .blog
        case "for-you", "forYou", "recent", "everyone", "latest", "trending": self = .forYou
        default: return nil
        }
    }
}

struct HomeFeedItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case note(Note)
        case post(FeedItem)
        case remote(RemoteStreamItem)
    }

    var kind: Kind
    var replies: [ReplyPreview] = []

    struct ReplyPreview: Decodable, Hashable, Identifiable {
        let id: Int64
        let author: Author
        let body: String
    }

    var replyTotal: Int64 {
        switch kind {
        case .note(let note): Int64(note.replyCount)
        case .post(let post): post.commentCount ?? 0
        case .remote(.trending(let note)): note.replyCount
        case .remote(.kept(let note)): Int64(note.replyCount)
        }
    }

    var id: String {
        switch kind {
        case .note(let note): "note-\(note.id)"
        case .post(let post): "post-\(post.id)"
        case .remote(let item): "remote-\(item.id)"
        }
    }

    var date: Date? {
        switch kind {
        case .note(let note): note.createdAt
        case .post(let post): post.publishedAt
        case .remote(.trending(let note)): note.createdAt
        case .remote(.kept(let note)): note.createdAt
        }
    }

    var note: Note? {
        if case .note(let note) = kind { return note }
        return nil
    }

    var keptNote: Note? {
        if case .remote(.kept(let note)) = kind { return note }
        return nil
    }
}

struct HomeFeedBatch: Decodable {
    let items: [HomeFeedItem]
    let next: String?
    var newest: String? = nil
    var gap: Bool? = nil
}

extension HomeFeedItem: Decodable {
    private enum CodingKeys: String, CodingKey { case kind, note, post, remote, replies }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "post": kind = .post(try container.decode(FeedItem.self, forKey: .post))
        case "remote": kind = .remote(try container.decode(RemoteStreamItem.self, forKey: .remote))
        default: kind = .note(try container.decode(Note.self, forKey: .note))
        }
        replies = (try? container.decodeIfPresent([ReplyPreview].self, forKey: .replies)) ?? []
    }
}

enum HomeFeedAPI {
    static var client = APIClient.shared
    static let limit = 20

    static func newer(_ tab: HomeFeedTab, since: String) async throws -> HomeFeedBatch {
        let query = tab.query(["limit": String(limit), "since": since])
        return tab.requiresAuth
            ? try await client.get("/public/home", query: query, authenticated: true)
            : try await client.getAsViewer("/public/home", query: query, headers: tab.headers)
    }

    static func page(_ tab: HomeFeedTab, cursor: String?) async throws -> HomeFeedBatch {
        do {
            let query = tab.query(["limit": String(limit), "cursor": cursor])
            let ticket = HomeFeedCache.shared.ticket()
            let data = tab.requiresAuth
                ? try await client.getAuthenticatedData("/public/home", query: query)
                : try await client.getDataAsViewer("/public/home", query: query, headers: tab.headers)
            let batch: HomeFeedBatch
            do {
                batch = try JSONDecoder.blog.decode(HomeFeedBatch.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
            if cursor == nil { HomeFeedCache.shared.store(data, batch: batch, tab: tab, ticket: ticket) }
            return batch
        } catch APIError.server(let status, _, _) where status == 404 || status == 405 {
            return try await merged(tab, page: cursor.flatMap { Int($0.dropFirst()) } ?? 0)
        }
    }

    static func merged(_ tab: HomeFeedTab, page: Int) async throws -> HomeFeedBatch {
        async let notes = notePage(tab, page: page)
        async let posts = postPage(tab, page: page)
        let (noteFeed, postFeed) = try await (notes, posts)
        let items = merge(
            notes: noteFeed.items.map { HomeFeedItem(kind: .note($0)) },
            posts: postFeed.items.map { HomeFeedItem(kind: .post($0)) },
            byTime: true)
        return HomeFeedBatch(items: items, next: noteFeed.hasNext || postFeed.hasNext ? "f\(page + 1)" : nil)
    }

    static func merge(notes: [HomeFeedItem], posts: [HomeFeedItem], byTime: Bool) -> [HomeFeedItem] {
        guard byTime else {
            var out: [HomeFeedItem] = []
            var n = notes.makeIterator(), p = posts.makeIterator()
            var nextNote = n.next(), nextPost = p.next()
            while nextNote != nil || nextPost != nil {
                for _ in 0..<2 { if let note = nextNote { out.append(note); nextNote = n.next() } }
                if let post = nextPost { out.append(post); nextPost = p.next() }
            }
            return out
        }
        return (notes + posts).enumerated().sorted { lhs, rhs in
            let l = lhs.element.date ?? .distantPast, r = rhs.element.date ?? .distantPast
            return l == r ? lhs.offset < rhs.offset : l > r
        }.map(\.element)
    }

    private static func notePage(_ tab: HomeFeedTab, page: Int) async throws -> NoteFeed {
        switch tab {
        case .following:
            guard await AuthStore.shared.isSignedIn else { return NoteFeed(items: [], page: 0, hasNext: false) }
            return try await NoteAPI.following(page: page)
        case .forYou: return try await NoteAPI.everyone(page: page)
        case .blog: return NoteFeed(items: [], page: 0, hasNext: false)
        }
    }

    private static func postPage(_ tab: HomeFeedTab, page: Int) async throws -> PublicFeedView {
        switch tab {
        case .following:
            guard await AuthStore.shared.isSignedIn else {
                return PublicFeedView(items: [], page: 0, size: 20, hasNext: false)
            }
            return try await LibraryAPI.followingFeed(page: page)
        case .forYou, .blog: return try await BlogAPI.feed(sort: .recent, page: page)
        }
    }
}
