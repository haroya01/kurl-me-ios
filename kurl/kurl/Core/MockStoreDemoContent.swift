//
//  MockStoreDemoContent.swift
//  kurl
//

import Foundation

extension MockStoreDemo {
    struct Person {
        let id: Int64
        let username: String
        let name: String
        let avatar: String?
    }

    static func pic(_ id: Int, _ width: Int, _ height: Int) -> String {
        "https://picsum.photos/id/\(id)/\(width)/\(height)"
    }

    private static func person(_ role: Int, avatar: String?) -> Person {
        Person(id: Int64(21 + role), username: copy.handles[role], name: copy.names[role], avatar: avatar)
    }

    static var essayist: Person { person(0, avatar: pic(82, 300, 300)) }
    static var reader: Person { person(1, avatar: nil) }
    static var cook: Person { person(2, avatar: pic(63, 300, 300)) }
    static var traveler: Person { person(3, avatar: pic(49, 300, 300)) }
    static var developer: Person { person(4, avatar: nil) }
    static var noter: Person { person(5, avatar: pic(40, 300, 300)) }

    static var cast: [Person] { [essayist, reader, cook, traveler, developer, noter] }

    static func person(_ username: String) -> Person? {
        cast.first { $0.username == username }
    }

    static func avatar(_ username: String) -> String? {
        guard isOn else { return nil }
        return person(username)?.avatar
    }

    static func author(_ p: Person) -> [String: Any] {
        ["id": p.id, "username": p.username, "bio": NSNull(),
         "avatarUrl": p.avatar ?? NSNull(), "displayName": p.name]
    }

    static func iso(hoursAgo: Double) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-hoursAgo * 3_600))
    }

    struct Post {
        let id: Int64
        let author: Person
        let slug: String
        let title: String
        let excerpt: String
        let tags: [String]
        let cover: String?
        let hoursAgo: Double
    }

    private static func post(_ index: Int, _ author: Person, _ slug: String, cover: Int?, hoursAgo: Double) -> Post {
        Post(
            id: Int64(9301 + index), author: author, slug: slug, title: copy.postTitles[index],
            excerpt: copy.postExcerpts[index], tags: copy.postTags[index],
            cover: cover.map { pic($0, 600, 600) }, hoursAgo: hoursAgo)
    }

    static var walkingPace: Post { post(0, essayist, "walking-pace", cover: 301, hoursAgo: 2) }
    static var potatoSoup: Post { post(1, cook, "sunday-potato-soup", cover: 292, hoursAgo: 5) }
    static var rereadBooks: Post { post(2, reader, "reread-three-books", cover: 24, hoursAgo: 20) }
    static var lisbon: Post { post(3, traveler, "lisbon-tram-28", cover: 419, hoursAgo: 26) }
    static var sideProject: Post { post(4, developer, "side-project-one-year", cover: nil, hoursAgo: 50) }
    static var rainSongs: Post { post(5, noter, "rainy-day-songs", cover: 171, hoursAgo: 75) }
    static var bookstore: Post { post(6, essayist, "last-day-of-bookstore", cover: nil, hoursAgo: 98) }
    static var transcription: Post { post(7, reader, "transcription-100-days", cover: 20, hoursAgo: 140) }

    static var posts: [Post] {
        [walkingPace, potatoSoup, rereadBooks, lisbon, sideProject, rainSongs, bookstore, transcription]
    }

    static func feedItem(_ p: Post) -> [String: Any] {
        ["id": p.id, "author": author(p.author), "slug": p.slug, "title": p.title, "excerpt": p.excerpt,
         "ogImageUrl": p.cover ?? NSNull(), "languageTag": copy.languageTag, "tags": p.tags,
         "publishedAt": iso(hoursAgo: p.hoursAgo), "viewCount": 0, "likeCount": 0]
    }

    static func listItem(_ p: Post, pinned: Bool = false) -> [String: Any] {
        ["id": p.id, "slug": p.slug, "title": p.title, "excerpt": p.excerpt,
         "ogImageUrl": p.cover ?? NSNull(), "languageTag": copy.languageTag, "tags": p.tags,
         "likeCount": 0, "pinned": pinned, "lastEditedAt": NSNull(),
         "publishedAt": iso(hoursAgo: p.hoursAgo)]
    }

    static func ordered(_ raw: [[String: Any]]) -> [[String: Any]] {
        raw.enumerated().map { i, block in
            var b = block
            b["blockOrder"] = i
            return b
        }
    }

    static func jsonString(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static var walkingPaceBlocks: [[String: Any]] {
        let c = copy
        return ordered([
            ["type": "PARAGRAPH", "content": c.opening],
            ["type": "PARAGRAPH", "content": c.fastReading],
            ["type": "H2", "content": c.underlineHeading],
            ["type": "PARAGRAPH", "content": c.underline],
            ["type": "QUOTE", "content": c.pullQuote],
            ["type": "PARAGRAPH", "content": c.threeReads],
            ["type": "IMAGE", "content": jsonString(["url": pic(301, 1200, 800), "caption": c.photoCaption])],
            ["type": "H2", "content": c.walkingHeading],
            ["type": "PARAGRAPH", "content": c.walking],
            ["type": "LIST_BULLET", "content": jsonString(c.steps)],
            ["type": "PARAGRAPH", "content": c.closing],
        ])
    }

    static func blocks(for p: Post) -> [[String: Any]] {
        if p.id == walkingPace.id { return walkingPaceBlocks }
        return ordered([["type": "PARAGRAPH", "content": p.excerpt]])
    }

    static func highlight(
        _ id: Int, _ by: Person, block: Int, _ quote: String, note: String? = nil, hoursAgo: Double
    ) -> [String: Any] {
        let content = walkingPaceBlocks[block]["content"] as? String ?? ""
        let range = (content as NSString).range(of: quote)
        return [
            "id": id,
            "author": ["id": by.id, "username": by.username, "bio": NSNull(),
                       "avatarUrl": by.avatar ?? NSNull(), "displayName": by.name],
            "blockOrder": block, "startOffset": range.location, "endOffset": range.location + range.length,
            "quote": quote, "note": note ?? NSNull(), "createdAt": iso(hoursAgo: hoursAgo),
        ]
    }

    static let threadHighlightId = 6201

    static func reply(_ id: Int, _ by: Person, _ body: String, hoursAgo: Double, likes: Int = 0) -> [String: Any] {
        ["id": id,
         "author": ["id": by.id, "username": by.username, "bio": NSNull(),
                    "avatarUrl": by.avatar ?? NSNull(), "displayName": by.name],
         "body": body, "createdAt": iso(hoursAgo: hoursAgo), "likeCount": likes]
    }

    static func belonging(_ collectionId: Int64, curator: Person, position: Int, total: Int) -> [String: Any] {
        ["id": collectionId, "title": copy.pathTitle, "description": NSNull(), "visibility": "PUBLIC", "kind": "PATH",
         "count": total, "updatedAt": iso(hoursAgo: 1), "preview": [] as [String],
         "curatorUsername": curator.username, "position": position, "total": total]
    }
}

extension MockBackend {
    static var storeDemoDisplayNames: [String: String] {
        Dictionary(uniqueKeysWithValues: MockStoreDemo.cast.map { ($0.username, $0.name) })
    }

    static var storeDemoPosts: [MockPost] {
        let c = MockStoreDemo.copy
        let draft = MockPost(
            id: 9401, slug: "late-autumn-walk", title: c.draftTitle, status: "DRAFT",
            markdown: c.draftBody, publishedAt: nil, updatedAt: Date().addingTimeInterval(-600),
            tags: [c.draftTag],
            excerpt: c.draftBody.components(separatedBy: "\n").first?.replacingOccurrences(of: "**", with: ""))
        let published = c.published.enumerated().map { i, p in
            MockPost(
                id: 9402 + Int64(i), slug: "published-\(i + 1)", title: p.title, status: "PUBLISHED",
                markdown: p.excerpt, publishedAt: Date().addingTimeInterval(-Double(3 + i * 6) * 86_400),
                updatedAt: Date().addingTimeInterval(-Double(3 + i * 6) * 86_400),
                tags: [p.tag], excerpt: p.excerpt)
        }
        return [draft] + published
    }

    private static func demoNote(
        _ id: Int64, _ by: MockStoreDemo.Person, minutesAgo: Double, _ body: String, replyTo: Int64? = nil
    ) -> MockNote {
        MockNote(
            id: id, body: body, createdAt: Date().addingTimeInterval(-minutesAgo * 60), likeCount: 0,
            authorId: by.id, username: by.username, inReplyToId: replyTo)
    }

    private static func photo(_ id: Int, _ alt: String, _ width: Int, _ height: Int) -> [String: Any] {
        ["url": MockStoreDemo.pic(id, width, height), "altText": alt, "contentType": "image/jpeg",
         "width": width, "height": height]
    }

    static var storeDemoNotes: [MockNote] {
        typealias S = MockStoreDemo
        let c = S.copy
        let thread = demoNote(9701, S.noter, minutesAgo: 12, c.threadRoot)
        var photos = demoNote(9702, S.traveler, minutesAgo: 40, c.photosNote)
        photos.media = [
            photo(322, c.photoAlts[0], 900, 1200),
            photo(308, c.photoAlts[1], 1200, 900),
            photo(369, c.photoAlts[2], 1200, 900),
        ]
        var poll = demoNote(9703, S.cook, minutesAgo: 70, c.pollNote)
        poll.poll = MockPoll(
            options: c.pollOptions, expiresAt: Date().addingTimeInterval(20 * 3_600), votes: [14, 9, 6], voters: 29)
        var quote = demoNote(9704, S.reader, minutesAgo: 130, c.quoteNote)
        quote.quotedPost = [
            "id": S.walkingPace.id, "title": S.walkingPace.title, "slug": S.walkingPace.slug,
            "authorUsername": S.essayist.username,
        ]
        var link = demoNote(9705, S.developer, minutesAgo: 200, c.linkNote)
        link.linkPreview = [
            "url": "https://blog.kurl.me/@\(S.developer.username)/slow-web", "title": c.linkTitle,
            "description": c.linkDescription, "image": S.pic(48, 960, 502),
        ]
        let walk = demoNote(9706, S.essayist, minutesAgo: 320, c.walkNote)
        let book = demoNote(9707, S.traveler, minutesAgo: 1_500, c.bookNote)
        return [thread, photos, poll, quote, link, walk, book]
    }

    static var storeDemoNoteReplies: [MockNote] {
        typealias S = MockStoreDemo
        let c = S.copy
        return [
            demoNote(9711, S.noter, minutesAgo: 11.9, c.threadParts[0], replyTo: 9701),
            demoNote(9712, S.noter, minutesAgo: 11.8, c.threadParts[1], replyTo: 9711),
            demoNote(9713, S.noter, minutesAgo: 11.7, c.threadParts[2], replyTo: 9712),
            demoNote(9721, S.essayist, minutesAgo: 8, c.threadThanks, replyTo: 9701),
            demoNote(9731, S.reader, minutesAgo: 30, c.pollReply, replyTo: 9703),
            demoNote(9741, S.noter, minutesAgo: 1_400, c.bookReply, replyTo: 9707),
        ]
    }

    static var storeDemoHighlights: [[String: Any]] {
        typealias S = MockStoreDemo
        let c = S.copy
        return [
            S.highlight(6202, S.reader, block: 1, c.topQuote, hoursAgo: 1.5),
            S.highlight(6203, S.cook, block: 1, c.topQuote, hoursAgo: 1.2),
            S.highlight(6204, S.traveler, block: 1, c.topQuote, hoursAgo: 0.8),
            S.highlight(S.threadHighlightId, S.noter, block: 3, c.threadQuote, note: c.threadNote, hoursAgo: 1),
            S.highlight(6205, S.developer, block: 5, c.pairQuote, hoursAgo: 0.6),
            S.highlight(6206, S.reader, block: 5, c.pairQuote, hoursAgo: 0.5),
        ]
    }

    static var storeDemoHighlightReplies: [Int: [[String: Any]]] {
        typealias S = MockStoreDemo
        return [
            S.threadHighlightId: [
                S.reply(7201, S.essayist, S.copy.authorReply, hoursAgo: 0.7, likes: 4),
                S.reply(7202, S.reader, S.copy.readerReply, hoursAgo: 0.4, likes: 2),
            ],
        ]
    }

    static var storeDemoCollections: [MockCollection] {
        typealias S = MockStoreDemo
        let c = S.copy
        let walking = S.walkingPace, reread = S.rereadBooks, bookstore = S.bookstore
        let lisbon = S.lisbon, soup = S.potatoSoup
        return [
            MockCollection(
                id: 104, title: c.pathTitle, description: c.pathDescription, visibility: "PUBLIC", kind: "PATH",
                connections: [
                    MockConnection(
                        id: 801, blockType: "POST", why: c.pathWhys[0], title: walking.title,
                        excerpt: walking.excerpt, slug: walking.slug, username: S.essayist.username,
                        refId: walking.id),
                    MockConnection(
                        id: 802, blockType: "HIGHLIGHT", why: c.pathWhys[1], title: walking.title,
                        slug: walking.slug, username: S.essayist.username, quote: c.pullQuote),
                    MockConnection(
                        id: 803, blockType: "POST", why: c.pathWhys[2], title: reread.title,
                        excerpt: reread.excerpt, slug: reread.slug, username: S.reader.username, refId: reread.id),
                    MockConnection(
                        id: 804, blockType: "NOTE", why: c.pathWhys[3], username: S.noter.username,
                        body: c.threadRoot, refId: 9701),
                    MockConnection(
                        id: 805, blockType: "POST", why: c.pathWhys[4], title: bookstore.title,
                        excerpt: bookstore.excerpt, slug: bookstore.slug, username: S.essayist.username,
                        refId: bookstore.id),
                ],
                curator: S.reader.username),
            MockCollection(
                id: 101, title: c.weekendTitle, description: nil, visibility: "PUBLIC",
                connections: [
                    MockConnection(
                        id: 811, blockType: "POST", why: nil, title: lisbon.title, excerpt: lisbon.excerpt,
                        slug: lisbon.slug, username: S.traveler.username, refId: lisbon.id),
                    MockConnection(
                        id: 812, blockType: "POST", why: nil, title: soup.title, excerpt: soup.excerpt,
                        slug: soup.slug, username: S.cook.username, refId: soup.id),
                ]),
            MockCollection(
                id: 102, title: c.kitchenTitle, description: nil, visibility: "PRIVATE",
                connections: [
                    MockConnection(
                        id: 821, blockType: "POST", why: c.kitchenWhy, title: soup.title, excerpt: soup.excerpt,
                        slug: soup.slug, username: S.cook.username, refId: soup.id),
                ]),
        ]
    }

    static func storeDemoResponse(_ parts: [String]) -> Any? {
        typealias S = MockStoreDemo
        switch parts {
        case ["public", "posts"], ["feed", "following"]:
            return ["items": S.posts.map(S.feedItem), "page": 0, "size": 20, "hasNext": false,
                    "seriesNotes": [] as [Any]]
        case ["public", "series"], ["users", "me", "blocks"]:
            return [] as [Any]
        case ["public", "feed", "connections"]:
            let bookstore = S.bookstore
            let event: [String: Any] = [
                "id": 31, "curator": S.author(S.reader), "collectionId": 104, "collectionTitle": S.copy.pathTitle,
                "collectionKind": "PATH", "why": S.copy.connectionWhy,
                "connectedAt": S.iso(hoursAgo: 3), "blockType": "POST", "title": bookstore.title,
                "excerpt": bookstore.excerpt, "slug": bookstore.slug, "username": S.essayist.username,
                "quote": NSNull(), "body": NSNull(),
            ]
            return ["items": [event], "page": 0, "size": 6, "hasNext": false]
        case ["public", "posts", "collections"]:
            return [
                ["postId": S.walkingPace.id,
                 "collections": [S.belonging(104, curator: S.reader, position: 1, total: 5)]],
                ["postId": S.rereadBooks.id,
                 "collections": [S.belonging(104, curator: S.reader, position: 3, total: 5)]],
            ]
        default:
            break
        }
        if parts.count == 5, parts[0] == "public", parts[1] == "profiles", parts[3] == "posts",
           let post = S.posts.first(where: { $0.slug == parts[4] }) {
            return [
                "author": S.author(post.author),
                "post": S.listItem(post),
                "blocks": S.blocks(for: post),
                "series": NSNull(),
            ]
        }
        if parts.count == 4, parts[0] == "public", parts[1] == "profiles", parts[3] == "posts",
           let person = S.person(parts[2]) {
            return [
                "author": S.author(person),
                "posts": S.posts.filter { $0.author.username == person.username }.map { S.listItem($0) },
            ]
        }
        if parts.count == 6, parts[0] == "public", parts[1] == "graph", parts[5] == "related" {
            return [S.rereadBooks, S.bookstore].enumerated().map { i, p in
                ["blockType": "POST", "refId": p.id, "sharedCount": 3 - i, "title": p.title, "excerpt": p.excerpt,
                 "slug": p.slug, "username": p.author.username, "quote": NSNull(), "body": NSNull()] as [String: Any]
            }
        }
        if parts.count == 4, parts[0] == "public", parts[1] == "profiles", parts[3] == "kindred" {
            let kindred: [(S.Person, String?, Int)] = [
                (S.essayist, S.copy.bios[0], 6), (S.noter, nil, 4), (S.reader, S.copy.bios[1], 3),
            ]
            return kindred.filter { $0.0.username != parts[2] }.prefix(2).map { person, bio, shared in
                ["curator": ["id": person.id, "username": person.username, "bio": bio ?? NSNull(),
                             "avatarUrl": person.avatar ?? NSNull()],
                 "sharedItems": shared] as [String: Any]
            }
        }
        return nil
    }
}
