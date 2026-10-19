//
//  RemoteTrending.swift
//  kurl
//

import Foundation

struct TrendingAuthor: Decodable, Hashable {
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let url: String?
    let remoteId: Int64?
}

struct TrendingNote: Decodable, Hashable, Identifiable {
    let uri: String
    let body: String
    let createdAt: Date?
    let author: TrendingAuthor
    let media: [NoteMedia]
    let contentWarning: String?
    let sensitive: Bool
    let language: String?
    let replyCount: Int64
    let likeCount: Int64
    let repostCount: Int64?
    let poll: NotePoll?
    let linkPreview: NoteLinkPreview?
    let remote: RemoteNoteShape?
    let servers: [String]

    var id: String { uri }

    var authorRoute: Route? {
        author.remoteId.map { .remoteAccount(id: $0) }
    }

    var originalURL: URL? {
        [remote?.url, author.url].compactMap { $0 }
            .compactMap(URL.init(string:))
            .first { ["https", "http"].contains($0.scheme?.lowercased()) }
    }

    var displayNote: Note {
        var note = Note(
            id: Self.placeholderId(uri), body: body, createdAt: createdAt, editedAt: nil,
            likeCount: nil, likedByMe: nil,
            author: Author(
                id: 0, username: author.username, bio: nil, avatarUrl: author.avatarUrl,
                displayName: author.displayName, remoteId: 0, url: author.url),
            media: media, quotedPost: nil, inReplyToId: nil, replyCount: replyCount,
            repostCount: nil, repostedByMe: nil, quotedNote: nil, linkPreview: linkPreview)
        note.contentWarning = contentWarning
        note.sensitive = sensitive
        note.language = language
        note.poll = poll
        note.remote = remote
        return note
    }

    static func placeholderId(_ uri: String) -> Int64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in uri.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return -Int64(hash >> 2) - 1
    }
}

struct TrendingNotePage: Decodable {
    let items: [TrendingNote]
}

enum RemoteStreamItem: Decodable, Hashable, Identifiable {
    case trending(TrendingNote)
    case kept(Note)

    private enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(Int64.self, forKey: .id) != nil {
            self = .kept(try Note(from: decoder))
        } else {
            self = .trending(try TrendingNote(from: decoder))
        }
    }

    var id: String {
        switch self {
        case .trending(let item): "t-\(item.uri)"
        case .kept(let note): "n-\(note.id)"
        }
    }
}

struct RemoteStreamPage: Decodable {
    let items: [RemoteStreamItem]
    let next: String?
}

enum RemoteStreamFeed: String, CaseIterable, Hashable {
    case trending
    case latest

    var path: String {
        switch self {
        case .trending: "/federation/trending"
        case .latest: "/federation/latest"
        }
    }
}

struct KnownDomain: Decodable, Hashable {
    let domain: String
}

struct KnownDomainPage: Decodable {
    let items: [KnownDomain]
}

extension FederationAPI {
    static let trendingLimit = 20
    static let domainLimit = 5

    static func trending() async throws -> [TrendingNote] {
        let page: TrendingNotePage = try await client.getAsViewer(
            "/federation/trending", query: ["limit": String(trendingLimit)])
        return page.items
    }

    static func stream(_ feed: RemoteStreamFeed, cursor: String?) async throws -> RemoteStreamPage {
        let query: [String: String?] = ["limit": String(trendingLimit), "cursor": cursor]
        return try await client.getAsViewer(feed.path, query: query)
    }

    static func domains(prefix: String) async -> [String]? {
        do {
            let page: KnownDomainPage = try await client.get(
                "/federation/domains", query: ["prefix": prefix, "limit": String(domainLimit)])
            return page.items.map { $0.domain.lowercased() }
        } catch {
            return nil
        }
    }
}
