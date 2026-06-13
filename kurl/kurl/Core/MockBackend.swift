//
//  MockBackend.swift
//  kurl
//

import Foundation

/// `--mocks` 모드의 인증 표면 가짜 백엔드. 응답 JSON 은 백엔드 record 와 같은 필드명을 쓰므로
/// 실모드와 동일한 디코더·뷰 바인딩이 그대로 검증된다. 상태(좋아요·팔로우·글)는 메모리에 들고
/// 토글·작성 흐름이 왕복하도록 한다. 공개 읽기(/public/*)는 다루지 않는다 — 실서버로 흘려보냄.
@MainActor
enum MockBackend {

    // MARK: 상태

    private struct MockPost {
        var id: Int64
        var slug: String
        var title: String
        var status: String
        var markdown: String
        var publishedAt: Date?
        var updatedAt: Date
        var tags: [String] = []
        var excerpt: String?
        var seriesId: Int64?
        var ogImageUrl: String?
        var scheduledAt: Date?
    }

    private static var posts: [MockPost] = [
        MockPost(id: 9001, slug: "p-mock-1", title: "목 초안 — 헥사고날 정리", status: "DRAFT",
                 markdown: "# 헥사고날\n\n포트와 어댑터.", publishedAt: nil, updatedAt: Date(),
                 tags: ["개발"], excerpt: "포트와 어댑터로 다시 그린다."),
        MockPost(id: 9002, slug: "p-mock-2", title: "발행된 목 글", status: "PUBLISHED",
                 markdown: "# 발행됨\n\n본문.", publishedAt: Date().addingTimeInterval(-86_400), updatedAt: Date()),
    ]
    private struct MockNote {
        var id: Int64
        var body: String
        var createdAt: Date
        var likeCount: Int64
        var authorId: Int64
        var username: String
    }

    private static var notes: [MockNote] = [
        MockNote(id: 9501, body: "오늘 헥사고날 포트 이름 짓는 데 한 시간 썼다. 이름이 곧 경계라는 걸 다시 배운다.",
                 createdAt: Date().addingTimeInterval(-1_800), likeCount: 4, authorId: 2, username: "yuki_dev"),
        MockNote(id: 9502, body: "긴 글로 정리하기 전의 생각 조각을 둘 곳이 필요했는데, 노트가 딱 그 자리다.",
                 createdAt: Date().addingTimeInterval(-7_200), likeCount: 11, authorId: 1, username: "honggildong"),
        MockNote(id: 9503, body: "라이트 모드 캔버스를 순백에서 slate-50 으로 바꿨더니 카드가 비로소 떠 보인다. 배경은 색이 아니라 깊이다.",
                 createdAt: Date().addingTimeInterval(-26_000), likeCount: 7, authorId: 3, username: "reader_kim"),
    ]
    private static var nextNoteId: Int64 = 9600
    private static var likedNotes: Set<Int64> = []

    private static var nextId: Int64 = 9100
    private static var likes: [Int64: (count: Int64, liked: Bool)] = [:]
    private static var bookmarks: Set<Int64> = []
    private static var follows: [String: (following: Bool, count: Int64)] = [:]
    private static var subscriptions: [Int64: (subscribed: Bool, count: Int64)] = [:]

    // MARK: 라우팅

    /// 처리하면 응답 바디, 아니면 nil → 실네트워크로.
    static func respond(path: String, method: String, body: Data?) -> Data? {
        let parts = path.split(separator: "/").map(String.init)

        if method == "GET", parts == ["users", "me"] {
            return json(["id": 1, "email": "mock@kurl.me", "username": "honggildong", "avatarUrl": NSNull()])
        }

        // 노트는 공개 읽기까지 목으로 받는다 — 실서버에 아직 배포 전이라 fall-through 하면 404.
        if method == "GET", parts == ["public", "notes"] {
            return json([
                "items": notes.sorted { $0.createdAt > $1.createdAt }.map(noteView),
                "page": 0, "hasNext": false,
            ])
        }

        if method == "POST", parts == ["notes"] {
            let note = MockNote(
                id: nextNoteId, body: decode(body)["body"] as? String ?? "",
                createdAt: Date(), likeCount: 0, authorId: 1, username: "honggildong")
            nextNoteId += 1
            notes.insert(note, at: 0)
            return json(noteView(note))
        }

        if method == "GET", parts == ["notes", "like-status"] {
            return json(["likedIds": Array(likedNotes)])
        }

        if method == "DELETE", parts.count == 2, parts[0] == "notes" {
            let nid = Int64(parts[1]) ?? 0
            notes.removeAll { $0.id == nid }
            likedNotes.remove(nid)
            return json([:] as [String: Any])
        }

        if parts.count == 3, parts[0] == "notes", parts[2] == "like" {
            let nid = Int64(parts[1]) ?? 0
            if let idx = notes.firstIndex(where: { $0.id == nid }) {
                if method == "PUT", !likedNotes.contains(nid) {
                    likedNotes.insert(nid)
                    notes[idx].likeCount += 1
                }
                if method == "DELETE", likedNotes.contains(nid) {
                    likedNotes.remove(nid)
                    notes[idx].likeCount -= 1
                }
                return json(["liked": likedNotes.contains(nid), "likeCount": notes[idx].likeCount])
            }
            return json(["liked": method == "PUT", "likeCount": 0])
        }

        if method == "GET", parts == ["posts", "analytics", "overview"] {
            return json(analyticsOverview())
        }

        if method == "GET", parts == ["posts", "analytics", "posts"] {
            return json([
                "items": [
                    ["postId": 9002, "slug": "p-mock-2", "title": "발행된 목 글",
                     "viewCount": 812, "likeCount": 41, "followsGained": 6],
                    ["postId": 9001, "slug": "p-mock-1", "title": "목 초안 — 헥사고날 정리",
                     "viewCount": 287, "likeCount": 19, "followsGained": 2],
                    ["postId": 9003, "slug": "p-mock-3", "title": "조용한 웹로그라는 결정",
                     "viewCount": 145, "likeCount": 12, "followsGained": 0],
                ],
                "page": 0, "hasNext": false,
            ])
        }

        if method == "GET", parts == ["posts", "analytics", "series"] {
            return json([
                ["seriesId": 1, "slug": "hexagonal", "title": "헥사고날 전환기",
                 "postCount": 6, "subscriberCount": 14, "totalViews": 1930, "totalLikes": 72],
                ["seriesId": 2, "slug": "ios-build", "title": "iOS 앱 만들기",
                 "postCount": 3, "subscriberCount": 7, "totalViews": 640, "totalLikes": 25],
            ])
        }

        if method == "PATCH", parts.count == 2, parts[0] == "posts" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            let req = decode(body)
            if let title = req["title"] as? String { posts[idx].title = title }
            if let excerpt = req["excerpt"] as? String { posts[idx].excerpt = excerpt.isEmpty ? nil : excerpt }
            if let tags = req["tags"] as? [String] { posts[idx].tags = tags }
            posts[idx].updatedAt = Date()
            return json(postView(posts[idx]))
        }

        if method == "GET", parts == ["posts"] {
            return json(posts.sorted { $0.updatedAt > $1.updatedAt }.map(postView))
        }

        if method == "POST", parts == ["posts"] {
            let req = decode(body)
            let post = MockPost(
                id: nextId, slug: req["slug"] as? String ?? "p-mock",
                title: req["title"] as? String ?? "무제", status: "DRAFT",
                markdown: "", publishedAt: nil, updatedAt: Date())
            nextId += 1
            posts.append(post)
            return json(postView(post))
        }

        if parts.count == 3, parts[0] == "posts", parts[2] == "markdown" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            if method == "PUT" {
                posts[idx].markdown = decode(body)["markdown"] as? String ?? ""
                posts[idx].updatedAt = Date()
            }
            return json(["markdown": posts[idx].markdown])
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "publish" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts[idx].status = "PUBLISHED"
            posts[idx].publishedAt = Date()
            return json(postView(posts[idx]))
        }

        if parts.count == 3, parts[0] == "posts", parts[2] == "like" {
            let pid = Int64(parts[1]) ?? 0
            var state = likes[pid] ?? (count: 3, liked: false)
            if method == "PUT" { if !state.liked { state.count += 1 }; state.liked = true }
            if method == "DELETE" { if state.liked { state.count -= 1 }; state.liked = false }
            likes[pid] = state
            return json(["likeCount": state.count, "liked": state.liked])
        }

        if parts.count == 3, parts[0] == "posts", parts[2] == "bookmark" {
            let pid = Int64(parts[1]) ?? 0
            if method == "PUT" { bookmarks.insert(pid) }
            if method == "DELETE" { bookmarks.remove(pid) }
            return json(["bookmarked": bookmarks.contains(pid)])
        }

        if parts.count == 3, parts[0] == "users", parts[2] == "follow" {
            let username = parts[1]
            var state = follows[username] ?? (following: false, count: 12)
            if method == "PUT" { if !state.following { state.count += 1 }; state.following = true }
            if method == "DELETE" { if state.following { state.count -= 1 }; state.following = false }
            follows[username] = state
            return json(["following": state.following, "followerCount": state.count, "followingCount": 5])
        }

        if parts.count == 3, parts[0] == "series", parts[2] == "subscription" {
            let sid = Int64(parts[1]) ?? 0
            var state = subscriptions[sid] ?? (subscribed: false, count: 7)
            if method == "PUT" { if !state.subscribed { state.count += 1 }; state.subscribed = true }
            if method == "DELETE" { if state.subscribed { state.count -= 1 }; state.subscribed = false }
            subscriptions[sid] = state
            return json(["subscribed": state.subscribed, "subscriberCount": state.count])
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "comments" {
            return json(["id": 1, "body": decode(body)["body"] as? String ?? ""])
        }

        if method == "GET", parts == ["bookmarks"] {
            return json([
                ["id": 9002, "username": "honggildong", "title": "발행된 목 글", "slug": "p-mock-2"],
                ["id": 9001, "username": "honggildong", "title": "목 초안 — 헥사고날 정리", "slug": "p-mock-1"],
            ])
        }

        if method == "GET", parts == ["users", "me", "likes"] {
            return json([feedItem(id: 9002, title: "발행된 목 글", slug: "p-mock-2")])
        }

        if method == "GET", parts == ["users", "me", "subscribed-series"] {
            return json([[
                "id": 1, "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
                "slug": "hexagonal", "title": "헥사고날 전환기", "postCount": 6,
                "lastPublishedAt": iso(Date().addingTimeInterval(-86_400)),
                "posts": [["slug": "p-mock-2", "title": "발행된 목 글"]],
            ]])
        }

        if method == "GET", parts == ["feed", "following"] {
            return json([
                "items": [feedItem(id: 9002, title: "발행된 목 글", slug: "p-mock-2")],
                "page": 0, "size": 20, "hasNext": false,
            ])
        }

        if parts.count == 3, parts[0] == "comments", parts[2] == "like" {
            let cid = Int64(parts[1]) ?? 0
            if method == "POST" { likedComments.insert(cid) }
            if method == "DELETE" { likedComments.remove(cid) }
            return json(["likeCount": likedComments.contains(cid) ? 3 : 2, "liked": likedComments.contains(cid)])
        }

        if method == "GET", parts.count == 4, parts[0] == "posts", parts[2] == "comments", parts[3] == "liked" {
            return json(Array(likedComments))
        }

        if method == "DELETE", parts.count == 2, parts[0] == "comments" {
            return json([:] as [String: Any])
        }

        if method == "GET", parts == ["notifications"] {
            return json([
                "items": [
                    ["id": 1, "type": "LIKE", "actorUsername": "reader_kim", "actorAvatarUrl": NSNull(),
                     "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "read": false, "createdAt": iso(Date().addingTimeInterval(-600))],
                    ["id": 2, "type": "COMMENT", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                     "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "read": false, "createdAt": iso(Date().addingTimeInterval(-3600))],
                    ["id": 3, "type": "FOLLOW", "actorUsername": "stranger99", "actorAvatarUrl": NSNull(),
                     "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "read": true, "createdAt": iso(Date().addingTimeInterval(-86_400))],
                    ["id": 4, "type": "SERIES_SUBSCRIBE", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                     "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                     "seriesId": 1, "seriesSlug": "hexagonal", "seriesTitle": "헥사고날 전환기",
                     "read": true, "createdAt": iso(Date().addingTimeInterval(-172_800))],
                ],
                "nextCursor": NSNull(), "hasMore": false,
            ])
        }

        if method == "GET", parts == ["notifications", "unread-count"] {
            return json(["count": 2])
        }

        if method == "POST", parts.count == 3, parts[0] == "notifications", parts[2] == "read" {
            return json([:] as [String: Any])
        }

        if method == "POST", parts == ["notifications", "read-all"] {
            return json(["count": 0])
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "preview-token" {
            return json(["token": "mock-preview-token"])
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "schedule" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts[idx].status = "SCHEDULED"
            posts[idx].scheduledAt = Date().addingTimeInterval(3600)
            return json(postView(posts[idx]))
        }

        if method == "GET", parts.count == 3, parts[0] == "posts", parts[2] == "revisions" {
            return json([
                ["id": 1, "versionNumber": 2, "titleSnapshot": "두 번째 저장", "createdAt": iso(Date().addingTimeInterval(-3600))],
                ["id": 2, "versionNumber": 1, "titleSnapshot": "첫 저장", "createdAt": iso(Date().addingTimeInterval(-7200))],
            ])
        }

        if method == "POST", parts.count == 5, parts[0] == "posts", parts[2] == "revisions", parts[4] == "restore" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts[idx].markdown = "# 복원된 본문 v\(parts[3])\n\n리비전에서 돌아왔다."
            return json(postView(posts[idx]))
        }

        if method == "POST", parts == ["series"] {
            let req = decode(body)
            let id = nextSeriesId
            nextSeriesId += 1
            createdSeries.append((id, req["slug"] as? String ?? "s-\(id)", req["title"] as? String ?? "시리즈"))
            seriesMembers[id] = []
            return json(["series": ["id": id, "slug": req["slug"] as? String ?? "s", "title": req["title"] as? String ?? "시리즈", "postCount": 0, "createdAt": iso(Date()), "updatedAt": iso(Date())], "posts": []])
        }

        if method == "GET", parts == ["series"] {
            return json((mockSeries + createdSeries).map { ["id": $0.0, "slug": $0.1, "title": $0.2, "postCount": seriesMembers[$0.0]?.count ?? 0, "createdAt": iso(Date()), "updatedAt": iso(Date())] })
        }

        if method == "GET", parts.count == 2, parts[0] == "series" {
            let sid = Int64(parts[1]) ?? 0
            let members = (seriesMembers[sid] ?? []).compactMap { id in posts.first { $0.id == id } }
            return json([
                "series": ["id": sid, "slug": "s", "title": "시리즈", "postCount": members.count, "createdAt": iso(Date()), "updatedAt": iso(Date())],
                "posts": members.map(postView),
            ])
        }

        if method == "PUT", parts.count == 3, parts[0] == "series", parts[2] == "posts" {
            let sid = Int64(parts[1]) ?? 0
            let ids = (decode(body)["postIds"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.int64Value }
            seriesMembers[sid] = ids
            for i in posts.indices {
                if ids.contains(posts[i].id) { posts[i].seriesId = sid }
                else if posts[i].seriesId == sid { posts[i].seriesId = nil }
            }
            return json(["series": ["id": sid, "slug": "s", "title": "시리즈", "postCount": ids.count, "createdAt": iso(Date()), "updatedAt": iso(Date())], "posts": []])
        }

        if method == "POST", parts.count == 4, parts[0] == "posts", parts[2] == "images", parts[3] == "presign" {
            return json([
                "uploadUrl": "https://mock-upload.invalid/put",
                "publicUrl": "https://cdn.kurl.me/mock-cover.jpg",
                "key": "mock/cover.jpg", "contentType": "image/jpeg", "maxBytes": 5_242_880,
            ])
        }

        if method == "POST", parts.count == 4, parts[0] == "posts", parts[2] == "images", parts[3] == "commit" {
            return json(["imageUrl": "https://cdn.kurl.me/mock-cover.jpg", "key": "mock/cover.jpg"])
        }

        return nil
    }

    private static let mockSeries: [(Int64, String, String)] = [
        (1, "hexagonal", "헥사고날 전환기"),
        (2, "ios-build", "iOS 앱 만들기"),
    ]
    private static var seriesMembers: [Int64: [Int64]] = [1: [9002], 2: []]
    private static var createdSeries: [(Int64, String, String)] = []
    private static var nextSeriesId: Int64 = 100
    private static var likedComments: Set<Int64> = []

    private static func feedItem(id: Int64, title: String, slug: String) -> [String: Any] {
        [
            "id": id,
            "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
            "slug": slug, "title": title, "excerpt": "목 발췌",
            "ogImageUrl": NSNull(), "languageTag": "ko", "tags": ["목"],
            "publishedAt": iso(Date().addingTimeInterval(-3600)),
            "viewCount": 42, "likeCount": 3,
        ]
    }

    // MARK: 픽스처

    private static func noteView(_ n: MockNote) -> [String: Any] {
        [
            "id": n.id, "body": n.body, "createdAt": iso(n.createdAt), "likeCount": n.likeCount,
            "author": ["id": n.authorId, "username": n.username, "avatarUrl": NSNull()],
        ]
    }

    private static func postView(_ p: MockPost) -> [String: Any] {
        [
            "id": p.id, "slug": p.slug, "title": p.title, "status": p.status,
            "languageTag": "ko",
            "publishedAt": p.publishedAt.map(iso) ?? NSNull(),
            "scheduledAt": p.scheduledAt.map(iso) ?? NSNull(),
            "excerpt": p.excerpt ?? NSNull(),
            "ogImageUrl": p.ogImageUrl ?? NSNull(),
            "seriesId": p.seriesId ?? NSNull(),
            "viewCount": 42, "likeCount": 3, "tags": p.tags,
            "createdAt": iso(p.updatedAt), "updatedAt": iso(p.updatedAt),
        ]
    }

    private static func analyticsOverview() -> [String: Any] {
        let calendar = Calendar(identifier: .gregorian)
        let daily: [[String: Any]] = (0..<30).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return ["date": fmt.string(from: day), "views": Int.random(in: 8...90)]
        }
        return [
            "totalPosts": 24, "publishedPosts": 21,
            "lifetimeViews": 5421, "lifetimeLikes": 132,
            "windowDays": 30, "windowViews": 1284,
            "lifetimeLinkClicks": 310, "windowLinkClicks": 57,
            "lifetimeFollows": 48, "windowFollows": 6,
            "daily": daily,
            "referrers": [
                ["host": "google.com", "views": 412],
                ["host": "t.co", "views": 187],
                ["host": "news.hada.io", "views": 96],
                ["host": "kurl.me", "views": 44],
            ],
        ]
    }

    // MARK: 유틸

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func decode(_ body: Data?) -> [String: Any] {
        guard let body,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
    }
}
