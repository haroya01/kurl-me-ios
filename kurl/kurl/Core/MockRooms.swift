import Foundation

#if DEBUG
enum MockRooms {
    private struct Room {
        var id: Int64
        var name: String
        var owner: Bool
        var hiddenFromFeed: Bool
        var approval: Bool
        var unread: Int64
        var members: [Person]
        var pinned = false
    }

    private struct Person {
        let id: Int64
        let username: String
        let displayName: String?
    }

    private struct Post {
        let id: Int64
        let roomId: Int64
        let author: Person
        let body: String
        let minutesAgo: Double
        var quotedNoteId: Int64? = nil
        var quotedPostId: Int64? = nil
        var media: [[String: Any]] = []
    }

    private static let me = Person(id: 1, username: "honggildong", displayName: "홍길동")
    private static let minji = Person(id: 31, username: "minji", displayName: "민지")
    private static let junho = Person(id: 32, username: "junho", displayName: "준호")
    private static let yuki = Person(id: 2, username: "yuki_dev", displayName: nil)
    private static let kim = Person(id: 3, username: "reader_kim", displayName: "김독자")
    private static let eunseong = Person(id: 33, username: "eunseong", displayName: "은성")
    private static let haneul = Person(id: 34, username: "haneul", displayName: "하늘")
    private static let narae = Person(id: 35, username: "narae", displayName: "나래")
    private static let sora = Person(id: 36, username: "sora", displayName: "소라")
    private static let dohyun = Person(id: 38, username: "dohyun", displayName: "도현")
    private static let hanbit = Person(id: 37, username: "hanbit", displayName: nil)
    private static let mom = Person(id: 40, username: "mom_kim", displayName: "엄마")
    private static let sister = Person(id: 41, username: "seoyeon", displayName: "서연")

    private static let following: [Person] = [minji, junho, yuki, kim, haneul, sora, dohyun]
    private static let followers: [Person] = [minji, junho, eunseong, narae, kim]

    private static var rooms: [Room] = ProcessInfo.processInfo.arguments.contains("--rooms-empty") ? [] : [
        Room(id: 1, name: "동아리 사람들", owner: true, hiddenFromFeed: false, approval: false, unread: 3,
             members: [me, minji, junho, yuki]),
        Room(id: 2, name: "대학 동기", owner: false, hiddenFromFeed: false, approval: false, unread: 0,
             members: [kim, me, minji]),
        Room(id: 3, name: "헥사고날 스터디", owner: false, hiddenFromFeed: true, approval: true, unread: 0,
             members: [yuki, me, kim, junho]),
        Room(id: 5, name: "우리 가족", owner: true, hiddenFromFeed: true, approval: false, unread: 0,
             members: [me, mom, sister], pinned: true),
        Room(id: 7, name: "새로 만든 방", owner: true, hiddenFromFeed: false, approval: false, unread: 0,
             members: [me]),
        Room(id: 6, name: "제주 여행 2024", owner: false, hiddenFromFeed: false, approval: false, unread: 0,
             members: [minji, me, haneul, sora]),
    ]

    private static var posts: [Post] = [
        Post(id: 9901, roomId: 1, author: minji, body: "퇴근하다 한강 들름 바람 미쳤음", minutesAgo: 3),
        Post(id: 9902, roomId: 1, author: junho, body: "5키로 첨으로 안 쉬고 뛰었다 ㅋㅋ", minutesAgo: 9),
        Post(id: 9903, roomId: 1, author: yuki, body: "엠티 사진 정리중인데 왜케 많냐", minutesAgo: 52),
        Post(id: 9904, roomId: 2, author: kim, body: "졸업앨범 받음 우리과 페이지 개웃김", minutesAgo: 60 * 20),
        Post(id: 9906, roomId: 2, author: minji, body: "퇴근하고 공방 다니는데 첫 컵 망함 ㅠ", minutesAgo: 60 * 3),
        Post(id: 9907, roomId: 1, author: me, body: "필카 첫 롤 현상 맡김", minutesAgo: 60 * 6),
        Post(id: 9908, roomId: 1, author: junho, body: "어제 단체사진 보정 끝 표정 다 제각각 ㅋㅋ", minutesAgo: 60 * 27,
             media: [[
                "url": "https://picsum.photos/seed/kurl-room-group/900/600", "altText": "엠티 단체 사진",
                "contentType": "image/jpeg", "width": 900, "height": 600,
             ]]),
        Post(id: 9909, roomId: 5, author: mom, body: "김장 끝 허리 나감", minutesAgo: 60 * 24 * 12),
        Post(id: 9910, roomId: 6, author: haneul, body: "앨범 정리하다 옛날 사진 나옴 다들 애기네", minutesAgo: 60 * 24 * 40),
        Post(id: 9905, roomId: 3, author: yuki, body: "포트 어댑터 이름 짓다가 한시간 날림", minutesAgo: 60 * 24 * 5),
        Post(id: 9911, roomId: 1, author: yuki, body: "사진 고르는 기준은 블로그에 적어 둠", minutesAgo: 60 * 30,
             quotedPostId: 9301),
    ]

    private struct RoomPost {
        let id: Int64
        let roomId: Int64
        let author: Person
        let slug: String
        let title: String
        let excerpt: String
        let minutesAgo: Double
        let cover: String?
        let readMinutes: Int
    }

    private static let roomPosts: [RoomPost] = [
        RoomPost(id: 8801, roomId: 1, author: yuki, slug: "rainy-mt-night", title: "비 오던 엠티의 밤",
                 excerpt: "펜션 지붕을 두드리던 빗소리, 새벽 세 시까지 이어진 보드게임, 그리고 아무도 제대로 못 찍은 단체 사진 이야기.",
                 minutesAgo: 30, cover: "https://picsum.photos/seed/kurlmt/1200/675", readMinutes: 4),
        RoomPost(id: 8802, roomId: 2, author: kim, slug: "graduation-album", title: "졸업 앨범을 받은 날",
                 excerpt: "4년 동안 찍힌 내 얼굴은 생각보다 적었다. 대신 뒷모습이 자주 나왔다.",
                 minutesAgo: 60 * 5, cover: "https://picsum.photos/seed/kurlgrad/1200/675", readMinutes: 3),
        RoomPost(id: 8803, roomId: 5, author: sister, slug: "moms-kimchi", title: "엄마 김치 레시피 받아 적기",
                 excerpt: "\"적당히\"를 숫자로 바꾸는 데 전화 세 통이 걸렸다.",
                 minutesAgo: 60 * 24 * 2, cover: nil, readMinutes: 6),
    ]

    /// 방 글이 본문에 실은 같은 방의 노트(글 → 노트).
    private static let embedded: [Int64: Int64] = [8801: 9903]

    /// 방 밖의 공개 글. 방 노트 9903 의 주소를 실었지만 방 밖이라 링크로만 보인다.
    private static let outsidePost = (
        id: Int64(9301), author: yuki, slug: "picking-mt-photos", title: "삼백 장에서 열 장 고르기")

    private static var nextNoteId: Int64 = 9960

    private static var invites: [Int64: [[String: Any]]] = [:]
    private static var requests: [Int64: [Person]] = [1: [eunseong]]
    private static var suggested: [Person] = [minji, junho]
    private static var invitees: [Int64: [(person: Person, inviter: Int64)]] = [1: [(kim, 1)]]
    private static var received: [(room: Room, inviter: Person)] =
        ProcessInfo.processInfo.arguments.contains("--rooms-empty") ? [] : [
            (Room(id: 4, name: "주말 등산 모임", owner: false, hiddenFromFeed: false, approval: false, unread: 0,
                  members: [yuki, haneul, sora]), yuki),
        ]
    private static var nextRoomId: Int64 = 10
    private static var nextInviteId: Int64 = 100

    static func roomNotesForFollowing() -> [[String: Any]] {
        posts.filter { post in rooms.contains { $0.id == post.roomId && !$0.hiddenFromFeed } }
            .sorted { newerFirst($0, $1) }
            .prefix(2)
            .map(noteView)
    }

    static func respond(parts: [String], method: String, body: Data?) -> Data? {
        if parts == ["public", "home"], method == "GET",
           ProcessInfo.processInfo.arguments.contains("--mock-home-rooms") {
            let notes: [[String: Any]] = roomNotesForFollowing().map { ["kind": "note", "note": $0] }
            let post: [[String: Any]] = roomPosts.prefix(1).map { ["kind": "post", "post": postView($0)] }
            return json(["items": Array(notes.prefix(1)) + post + Array(notes.dropFirst()), "next": NSNull()])
        }
        if method == "GET", parts.count == 3, parts[0] == "public", parts[1] == "notes",
           let id = Int64(parts[2]), let post = posts.first(where: { $0.id == id }) {
            let answers = (replies[id] ?? []).map { reply in
                noteView(Post(id: reply.0, roomId: post.roomId, author: reply.1, body: reply.2, minutesAgo: post.minutesAgo / 2))
            }
            return json([
                "note": noteView(post), "parent": NSNull(), "replies": answers,
                "continuation": [] as [Any], "series": NSNull(),
            ])
        }
        if parts == ["rooms"] {
            if method == "POST" {
                let name = (decode(body)["name"] as? String) ?? ""
                let room = Room(id: nextRoomId, name: name, owner: true, hiddenFromFeed: false, approval: false,
                                unread: 0, members: [me])
                nextRoomId += 1
                rooms.insert(room, at: 0)
                return json(detail(room))
            }
            if method == "GET" { return json(rooms.map(listItem)) }
        }
        if parts.count == 3, parts[0] == "users", parts[1] == me.username,
           parts[2] == "followers" || parts[2] == "following" {
            let people = parts[2] == "followers" ? followers : following
            return json([
                "items": people.map { p -> [String: Any] in
                    ["id": p.id, "username": p.username, "bio": NSNull(), "avatarUrl": NSNull(),
                     "followerCount": 10, "followedByMe": parts[2] == "following"]
                },
                "page": 0, "size": 20, "hasNext": false,
            ])
        }
        if parts == ["rooms", "items"], method == "GET" {
            let mine = Set(rooms.map(\.id))
            return json(["items": mixed(mine), "next": NSNull()])
        }
        if parts.count == 3, parts[0] == "rooms", parts[2] == "items", method == "GET", let id = Int64(parts[1]) {
            return json(["items": mixed([id]), "next": NSNull()])
        }
        if parts == ["rooms", "feed"], method == "GET" {
            let mine = Set(rooms.map(\.id))
            let items = posts.filter { mine.contains($0.roomId) }.sorted { newerFirst($0, $1) }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false])
        }
        if parts == ["rooms", "invitations"], method == "GET" {
            return json(received.map { item -> [String: Any] in
                ["roomId": item.room.id, "roomName": item.room.name, "memberCount": item.room.members.count,
                 "inviter": person(item.inviter), "approvalRequired": item.room.approval,
                 "invitedAt": iso(minutesAgo: 40)]
            })
        }
        if parts.count == 4, parts[0] == "rooms", parts[1] == "invitations", let id = Int64(parts[2]),
           method == "POST" {
            guard let at = received.firstIndex(where: { $0.room.id == id }) else { return nil }
            var room = received.remove(at: at).room
            if parts[3] == "accept" {
                room.members.append(me)
                rooms.insert(room, at: 0)
                return json(["status": "joined", "roomId": id])
            }
            return json([:])
        }
        if parts == ["rooms", "suggestions"], method == "GET" {
            return json(["friends": suggested.map(person)])
        }
        if parts == ["rooms", "suggestions", "dismiss"], method == "POST" {
            let ids = (decode(body)["userIds"] as? [Int64]) ?? []
            suggested.removeAll { ids.contains($0.id) }
            return json([:])
        }
        guard parts.count >= 2, parts[0] == "rooms", let id = Int64(parts[1]),
              let index = rooms.firstIndex(where: { $0.id == id })
        else { return nil }
        let rest = Array(parts.dropFirst(2))
        switch (method, rest) {
        case ("GET", []):
            return json(detail(rooms[index]))
        case ("PATCH", []):
            if let name = decode(body)["name"] as? String { rooms[index].name = name }
            if let approval = decode(body)["approvalRequired"] as? Bool { rooms[index].approval = approval }
            return json(detail(rooms[index]))
        case ("GET", ["notes"]):
            let items = posts.filter { $0.roomId == id }.sorted { newerFirst($0, $1) }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false])
        case ("POST", ["read"]):
            rooms[index].unread = 0
            return json(["unreadCount": 0])
        case ("PUT", ["feed-hidden"]), ("DELETE", ["feed-hidden"]):
            rooms[index].hiddenFromFeed = method == "PUT"
            return json(["hiddenFromFeed": rooms[index].hiddenFromFeed])
        case ("PUT", ["pin"]), ("DELETE", ["pin"]):
            rooms[index].pinned = method == "PUT"
            return Data()
        case ("POST", ["leave"]):
            rooms.remove(at: index)
            return json([:])
        case ("DELETE", let path) where path.count == 2 && path[0] == "members":
            rooms[index].members.removeAll { String($0.id) == path[1] }
            return json([:])
        case ("GET", ["invites"]):
            return json(invites[id] ?? [])
        case ("POST", ["invites"]):
            let options = decode(body)
            let code = "r\(nextInviteId)x"
            let invite: [String: Any] = [
                "id": nextInviteId, "code": code, "url": "https://kurl.me/R\(nextInviteId)k",
                "pageUrl": "https://blog.kurl.me/ko/rooms/join/\(code)",
                "maxUses": options["maxUses"] ?? NSNull(), "uses": 0,
                "approval": (options["approval"] as? Bool) ?? rooms[index].approval,
                "expiresAt": NSNull(), "disabled": false,
                "creator": person(me),
            ]
            nextInviteId += 1
            invites[id, default: []].insert(invite, at: 0)
            return json(invite)
        case ("DELETE", let path) where path.count == 2 && path[0] == "invites":
            guard var list = invites[id], let at = list.firstIndex(where: { "\($0["id"] ?? "")" == path[1] })
            else { return json([:]) }
            list[at]["disabled"] = true
            invites[id] = list
            return json(list[at])
        case ("GET", ["invitations"]):
            return json(inviteeViews(id))
        case ("POST", ["invitations"]):
            let ids = (decode(body)["userIds"] as? [Any])?.compactMap { ($0 as? NSNumber)?.int64Value } ?? []
            let known = following + followers + [haneul, hanbit, narae, sora, dohyun, eunseong, kim]
            for uid in ids where !rooms[index].members.contains(where: { $0.id == uid })
                && !(invitees[id] ?? []).contains(where: { $0.person.id == uid }) {
                if let who = known.first(where: { $0.id == uid }) {
                    invitees[id, default: []].insert((who, me.id), at: 0)
                }
            }
            return json(inviteeViews(id))
        case ("DELETE", let path) where path.count == 2 && path[0] == "invitations":
            invitees[id]?.removeAll { String($0.person.id) == path[1] }
            return json([:])
        case ("GET", ["requests"]):
            return json((requests[id] ?? []).map { ["person": person($0), "requestedAt": iso(minutesAgo: 30)] })
        case ("POST", let path) where path.count == 2 && path[0] == "requests":
            if let who = requests[id]?.first(where: { String($0.id) == path[1] }) { rooms[index].members.append(who) }
            requests[id]?.removeAll { String($0.id) == path[1] }
            return json([:])
        case ("DELETE", let path) where path.count == 2 && path[0] == "requests":
            requests[id]?.removeAll { String($0.id) == path[1] }
            return json([:])
        default:
            return nil
        }
    }

    // MARK: 인용

    /// 서버(NoteComposer)와 같은 쓰기 규칙 — 누구나 보는 것은 어디서나, 방의 것은 그 방에 올리는 노트만 인용한다.
    private static func checkQuote(_ draft: [String: Any]) throws {
        let roomId = (draft["roomId"] as? NSNumber)?.int64Value
        if let roomId, !rooms.contains(where: { $0.id == roomId }) {
            throw APIError.server(status: 404, code: "NOTE_ROOM_NOT_FOUND", detail: "room not found: \(roomId)")
        }
        if let quoted = (draft["quotedNoteId"] as? NSNumber)?.int64Value {
            let allowed: Bool
            if let roomNote = roomNote(quoted) {
                allowed = roomNote.roomId == roomId
            } else {
                allowed = MockBackend.noteVisibility(quoted).map { ["public", "unlisted"].contains($0) } ?? true
            }
            if !allowed {
                throw APIError.server(
                    status: 400, code: "NOTE_NOT_SHAREABLE",
                    detail: "only public and unlisted notes can be reposted or quoted")
            }
        }
        if let quoted = (draft["quotedPostId"] as? NSNumber)?.int64Value,
           let roomPost = roomPosts.first(where: { $0.id == quoted }), roomPost.roomId != roomId {
            throw APIError.server(
                status: 400, code: "NOTE_QUOTE_NOT_FOUND", detail: "quoted post is not published: \(quoted)")
        }
    }

    private static func createNote(_ draft: [String: Any], roomId: Int64) -> Post {
        let note = Post(
            id: nextNoteId, roomId: roomId, author: me, body: draft["body"] as? String ?? "", minutesAgo: 0,
            quotedNoteId: (draft["quotedNoteId"] as? NSNumber)?.int64Value,
            quotedPostId: (draft["quotedPostId"] as? NSNumber)?.int64Value)
        nextNoteId += 1
        posts.insert(note, at: 0)
        return note
    }

    static func quoteRoutes(parts: [String], method: String, body: Data?) throws -> Data? {
        if method == "POST", parts == ["notes"] {
            let draft = decode(body)
            try checkQuote(draft)
            guard let roomId = (draft["roomId"] as? NSNumber)?.int64Value else { return nil }
            return json(noteView(createNote(draft, roomId: roomId)))
        }
        if method == "POST", parts == ["notes", "threads"] {
            let drafts = (decode(body)["notes"] as? [[String: Any]]) ?? []
            for draft in drafts { try checkQuote(draft) }
            guard let roomId = (drafts.first?["roomId"] as? NSNumber)?.int64Value else { return nil }
            return json(drafts.map { noteView(createNote($0, roomId: roomId)) })
        }
        if method == "POST", parts == ["notes", "scheduled"] {
            try checkQuote(decode(body)["note"] as? [String: Any] ?? [:])
            return nil
        }
        guard method == "GET", parts.first == "public" else { return nil }
        if parts.count == 4, parts[1] == "notes", let id = Int64(parts[2]),
           let quoted = posts.first(where: { $0.id == id }) {
            if parts[3] == "quotes" {
                let items = posts.filter { $0.quotedNoteId == id && $0.roomId == quoted.roomId }
                    .sorted { newerFirst($0, $1) }.map(noteView)
                return json(["items": items, "page": 0, "hasNext": false])
            }
            if parts[3] == "posts" {
                let items = roomPosts.filter { embedded[$0.id] == id && $0.roomId == quoted.roomId }.map(postView)
                return json(["items": items, "page": 0, "size": 20, "hasNext": false])
            }
        }
        if parts.count == 4, parts[1] == "posts", parts[3] == "quotes", let id = Int64(parts[2]),
           let quoted = roomPosts.first(where: { $0.id == id }) {
            let items = posts.filter { $0.quotedPostId == id && $0.roomId == quoted.roomId }
                .sorted { newerFirst($0, $1) }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false, "total": items.count])
        }
        if parts.count == 5, parts[1] == "profiles", parts[3] == "posts" {
            if let post = roomPosts.first(where: { $0.slug == parts[4] }) {
                var blocks = [("PARAGRAPH", post.excerpt)]
                if let note = embedded[post.id].flatMap({ id in posts.first { $0.id == id } }) {
                    blocks.append(("EMBED", noteAddress(note)))
                }
                return json(detailView(
                    id: post.id, author: post.author, slug: post.slug, title: post.title, excerpt: post.excerpt,
                    minutesAgo: post.minutesAgo, blocks: blocks, room: rooms.first { $0.id == post.roomId }))
            }
            if parts[4] == outsidePost.slug, let note = posts.first(where: { $0.id == 9903 }) {
                return json(detailView(
                    id: outsidePost.id, author: outsidePost.author, slug: outsidePost.slug, title: outsidePost.title,
                    excerpt: "흔들린 사진부터 지운다. 그다음은 같은 장면이 겹친 것.", minutesAgo: 60 * 31,
                    blocks: [
                        ("PARAGRAPH", "흔들린 사진부터 지운다. 그다음은 같은 장면이 겹친 것."),
                        ("EMBED", noteAddress(note)),
                        ("PARAGRAPH", "남은 서른 장에서 열 장은 하룻밤 자고 고른다."),
                    ],
                    room: nil))
            }
        }
        return nil
    }

    private static func roomNote(_ id: Int64) -> Post? {
        if let note = posts.first(where: { $0.id == id }) { return note }
        for parent in posts {
            if let reply = replies[parent.id]?.first(where: { $0.0 == id }) {
                return Post(id: id, roomId: parent.roomId, author: reply.1, body: reply.2, minutesAgo: parent.minutesAgo / 2)
            }
        }
        return nil
    }

    private static func newerFirst(_ a: Post, _ b: Post) -> Bool {
        (a.minutesAgo, -a.id) < (b.minutesAgo, -b.id)
    }

    private static func noteAddress(_ note: Post) -> String {
        "\(Config.blogBase)/@\(note.author.username)/notes/\(note.id)"
    }

    private static func detailView(
        id: Int64, author: Person, slug: String, title: String, excerpt: String, minutesAgo: Double,
        blocks: [(String, String)], room: Room?
    ) -> [String: Any] {
        var post: [String: Any] = [
            "id": id, "slug": slug, "title": title, "excerpt": excerpt, "ogImageUrl": NSNull(),
            "languageTag": "ko", "tags": [String](), "likeCount": 2, "pinned": false, "lastEditedAt": NSNull(),
            "publishedAt": iso(minutesAgo: minutesAgo),
        ]
        if let room {
            post["audience"] = "ROOM"
            post["room"] = ["id": room.id, "name": room.name]
        }
        return [
            "author": [
                "id": author.id, "username": author.username, "bio": NSNull(), "avatarUrl": NSNull(),
                "displayName": author.displayName ?? NSNull(),
            ],
            "post": post,
            "blocks": blocks.enumerated().map { index, block in
                ["type": block.0, "content": block.1, "blockOrder": index] as [String: Any]
            },
            "series": NSNull(),
        ]
    }

    private static func quotedNoteView(_ post: Post) -> Any {
        guard let id = post.quotedNoteId else { return NSNull() }
        guard let quoted = roomNote(id) else {
            return MockBackend.quotedNoteView(id) ?? NSNull()
        }
        return [
            "id": quoted.id, "body": quoted.body, "createdAt": iso(minutesAgo: quoted.minutesAgo),
            "author": person(quoted.author), "media": quoted.media, "contentWarning": NSNull(), "sensitive": false,
        ] as [String: Any]
    }

    private static func quotedPostView(_ post: Post) -> Any {
        guard let id = post.quotedPostId else { return NSNull() }
        if let quoted = roomPosts.first(where: { $0.id == id }) {
            guard rooms.contains(where: { $0.id == quoted.roomId }) else { return NSNull() }
            return [
                "id": quoted.id, "title": quoted.title, "slug": quoted.slug,
                "authorUsername": quoted.author.username, "audience": "ROOM",
            ] as [String: Any]
        }
        if id == outsidePost.id {
            return [
                "id": id, "title": outsidePost.title, "slug": outsidePost.slug,
                "authorUsername": outsidePost.author.username, "audience": "PUBLIC",
            ] as [String: Any]
        }
        return [
            "id": id, "title": "인용한 글", "slug": "quoted", "authorUsername": me.username, "audience": "PUBLIC",
        ] as [String: Any]
    }

    private static let replies: [Int64: [(Int64, Person, String)]] = [
        9901: [(9951, junho, "나도 어제 거기 있었는데"), (9952, yuki, "사진 있으면 올려 줘요")],
        9902: [(9953, minji, "오 ㄷㄷ 다음엔 같이 뛰자")],
        8801: [(9954, minji, "단체 사진 진짜 한 장도 없는 거 실화냐"), (9955, junho, "보드게임 진 사람 누구였지"),
               (9956, me, "나야… 다음엔 이긴다")],
        8803: [(9957, mom, "적당히가 제일 정확한 건데")],
    ]

    private static func replyViews(_ id: Int64) -> [[String: Any]] {
        (replies[id] ?? []).prefix(2).map { ["id": $0.0, "author": person($0.1), "body": $0.2] }
    }

    private static func mixed(_ roomIds: Set<Int64>) -> [[String: Any]] {
        var entries: [(Double, Int64, [String: Any])] = posts.filter { roomIds.contains($0.roomId) }
            .map { ($0.minutesAgo, $0.id, ["kind": "note", "note": noteView($0), "replies": replyViews($0.id)]) }
        entries += roomPosts.filter { roomIds.contains($0.roomId) }
            .map { ($0.minutesAgo, $0.id, ["kind": "post", "post": postView($0), "replies": replyViews($0.id)]) }
        return entries.sorted { ($0.0, -$0.1) < ($1.0, -$1.1) }.map(\.2)
    }

    private static func postView(_ post: RoomPost) -> [String: Any] {
        let room = rooms.first { $0.id == post.roomId }
        return [
            "id": post.id, "author": ["id": post.author.id, "username": post.author.username, "bio": NSNull(),
                                      "avatarUrl": NSNull(), "displayName": post.author.displayName ?? NSNull()],
            "slug": post.slug, "title": post.title, "excerpt": post.excerpt,
            "ogImageUrl": post.cover ?? NSNull(), "thumbnailUrl": post.cover ?? NSNull(),
            "languageTag": "ko", "tags": [String](), "publishedAt": iso(minutesAgo: post.minutesAgo),
            "viewCount": 4, "likeCount": 2, "readMinutes": post.readMinutes, "commentCount": replies[post.id]?.count ?? 0,
            "room": ["id": post.roomId, "name": room?.name ?? ""],
        ]
    }

    private static func inviteeViews(_ id: Int64) -> [[String: Any]] {
        (invitees[id] ?? []).map {
            ["person": person($0.person), "inviterId": $0.inviter, "invitedAt": iso(minutesAgo: 10)]
        }
    }

    private static func listItem(_ room: Room) -> [String: Any] {
        let last = posts.filter { $0.roomId == room.id }.min { newerFirst($0, $1) }
        return [
            "id": room.id, "name": room.name, "memberCount": room.members.count,
            "role": room.owner ? "OWNER" : "MEMBER", "hiddenFromFeed": room.hiddenFromFeed,
            "unreadCount": room.unread,
            "pinned": room.pinned,
            "faces": room.members.filter { $0.id != me.id }.prefix(3).map(person),
            "lastActivityAt": last.map { iso(minutesAgo: $0.minutesAgo) } ?? NSNull(),
            "lastNote": last.map { post -> [String: Any] in
                ["id": post.id, "excerpt": post.body, "author": person(post.author),
                 "createdAt": iso(minutesAgo: post.minutesAgo)]
            } ?? NSNull(),
        ]
    }

    private static func detail(_ room: Room) -> [String: Any] {
        [
            "id": room.id, "name": room.name, "role": room.owner ? "OWNER" : "MEMBER",
            "approvalRequired": room.approval, "hiddenFromFeed": room.hiddenFromFeed,
            "memberCount": room.members.count,
            "members": room.members.enumerated().map { index, member in
                var shown = person(member)
                shown["role"] = index == 0 ? "OWNER" : "MEMBER"
                return shown
            },
        ]
    }

    private static func noteView(_ post: Post) -> [String: Any] {
        let room = rooms.first { $0.id == post.roomId }
        return [
            "id": post.id, "body": post.body, "createdAt": iso(minutesAgo: post.minutesAgo),
            "editedAt": NSNull(), "likeCount": 0, "likedByMe": false,
            "author": person(post.author),
            "media": post.media, "quotedPost": quotedPostView(post), "inReplyToId": NSNull(),
            "replyCount": replies[post.id]?.count ?? 0, "repostCount": 0, "repostedByMe": false, "bookmarkedByMe": false,
            "quoteCount": posts.filter { $0.quotedNoteId == post.id && $0.roomId == post.roomId }.count
                + roomPosts.filter { embedded[$0.id] == post.id && $0.roomId == post.roomId }.count,
            "linkPreview": NSNull(), "mentions": [Any](),
            "contentWarning": NSNull(), "sensitive": false, "pinned": false,
            "visibility": "room", "poll": NSNull(), "conversationMuted": false, "quotedNote": quotedNoteView(post),
            "room": ["id": post.roomId, "name": room?.name ?? ""],
        ]
    }

    private static func person(_ p: Person) -> [String: Any] {
        ["id": p.id, "username": p.username, "displayName": p.displayName ?? NSNull(), "avatarUrl": NSNull()]
    }

    private static func iso(minutesAgo: Double) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60))
    }

    private static func decode(_ body: Data?) -> [String: Any] {
        guard let body, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return obj
    }

    private static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
    }
}
#endif
