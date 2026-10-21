//
//  HomeFeedAPI.swift
//  kurl
//

import Foundation

enum HomeFeedTab: String, CaseIterable, Identifiable, Hashable {
    case following
    case latest
    case trending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .following: String(localized: "팔로잉")
        case .latest: String(localized: "최신")
        case .trending: String(localized: "인기")
        }
    }

    var symbol: String {
        switch self {
        case .following: "person.2"
        case .latest: "clock"
        case .trending: "flame"
        }
    }

    var requiresAuth: Bool { self == .following }

    init?(stored: String) {
        switch stored {
        case "following": self = .following
        case "recent", "everyone", "latest": self = .latest
        case "trending": self = .trending
        default: return nil
        }
    }
}

struct HomeFeedItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case note(Note)
        case post(FeedItem)
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
        }
    }

    var id: String {
        switch kind {
        case .note(let note): "note-\(note.id)"
        case .post(let post): "post-\(post.id)"
        }
    }

    var date: Date? {
        switch kind {
        case .note(let note): note.createdAt
        case .post(let post): post.publishedAt
        }
    }

    var note: Note? {
        if case .note(let note) = kind { return note }
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
    private enum CodingKeys: String, CodingKey { case kind, note, post, replies }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "post": kind = .post(try container.decode(FeedItem.self, forKey: .post))
        default: kind = .note(try container.decode(Note.self, forKey: .note))
        }
        replies = (try? container.decodeIfPresent([ReplyPreview].self, forKey: .replies)) ?? []
    }
}

enum HomeFeedAPI {
    static var client = APIClient.shared
    static let limit = 20

    static func newer(_ tab: HomeFeedTab, since: String) async throws -> HomeFeedBatch {
        let query: [String: String?] = ["tab": tab.rawValue, "limit": String(limit), "since": since]
        return tab.requiresAuth
            ? try await client.get("/public/home", query: query, authenticated: true)
            : try await client.getAsViewer("/public/home", query: query)
    }

    static func page(_ tab: HomeFeedTab, cursor: String?) async throws -> HomeFeedBatch {
        do {
            let query: [String: String?] = ["tab": tab.rawValue, "limit": String(limit), "cursor": cursor]
            return tab.requiresAuth
                ? try await client.get("/public/home", query: query, authenticated: true)
                : try await client.getAsViewer("/public/home", query: query)
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
            byTime: tab != .trending)
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
        case .latest: return try await NoteAPI.everyone(page: page)
        case .trending: return try await NoteAPI.trending(page: page)
        }
    }

    private static func postPage(_ tab: HomeFeedTab, page: Int) async throws -> PublicFeedView {
        switch tab {
        case .following:
            guard await AuthStore.shared.isSignedIn else {
                return PublicFeedView(items: [], page: 0, size: 20, hasNext: false)
            }
            return try await LibraryAPI.followingFeed(page: page)
        case .latest: return try await BlogAPI.feed(sort: .recent, page: page)
        case .trending: return try await BlogAPI.feed(sort: .trending, page: page)
        }
    }
}
