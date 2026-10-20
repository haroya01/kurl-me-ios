//
//  MockRooms.swift
//  kurl
//

import Foundation

enum MockRooms {
    private struct Room {
        var id: Int64
        var name: String
        var owner: Bool
        var hiddenFromFeed: Bool
        var approval: Bool
        var unread: Int64
        var members: [Person]
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

    private static let following: [Person] = [minji, junho, yuki, kim, haneul, sora, dohyun]
    private static let followers: [Person] = [minji, junho, eunseong, narae, kim]

    private static var rooms: [Room] = ProcessInfo.processInfo.arguments.contains("--rooms-empty") ? [] : [
        Room(id: 1, name: "동아리 사람들", owner: true, hiddenFromFeed: false, approval: false, unread: 3,
             members: [me, minji, junho, yuki]),
        Room(id: 2, name: "대학 동기", owner: false, hiddenFromFeed: false, approval: false, unread: 0,
             members: [kim, me, minji]),
        Room(id: 3, name: "헥사고날 스터디", owner: false, hiddenFromFeed: true, approval: true, unread: 0,
             members: [yuki, me, kim, junho]),
    ]

    private static var posts: [Post] = [
        Post(id: 9901, roomId: 1, author: minji, body: "내일 몇 시에 봐? 저녁 먹고 가도 될 듯", minutesAgo: 3),
        Post(id: 9902, roomId: 1, author: junho, body: "7시 어때. 역 앞 카페에서 모이자", minutesAgo: 9),
        Post(id: 9903, roomId: 1, author: yuki, body: "지난주 사진 정리해서 올릴게요", minutesAgo: 52),
        Post(id: 9904, roomId: 2, author: kim, body: "졸업 앨범 사진 받았어? 단체 사진 하나 더 있대", minutesAgo: 60 * 20),
        Post(id: 9906, roomId: 2, author: minji, body: "다음 달에 동기 모임 한번 하자. 날짜 몇 개 올려볼게", minutesAgo: 60 * 3),
        Post(id: 9907, roomId: 1, author: me, body: "다들 7시 괜찮으면 거기서 봐요", minutesAgo: 60 * 6),
        Post(id: 9908, roomId: 1, author: junho, body: "어제 찍은 사진 다들 받았지? 단체 사진은 내가 보정해서 다시 올릴게", minutesAgo: 60 * 27),
        Post(id: 9905, roomId: 3, author: yuki, body: "다음 주는 포트·어댑터 이름 짓기 정리해 올게요", minutesAgo: 60 * 24 * 5),
    ]

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
            .sorted { $0.minutesAgo < $1.minutesAgo }
            .prefix(2)
            .map(noteView)
    }

    static func respond(parts: [String], method: String, body: Data?) -> Data? {
        if parts == ["public", "home"], method == "GET",
           ProcessInfo.processInfo.arguments.contains("--mock-home-rooms") {
            return json(["items": roomNotesForFollowing().map { ["kind": "note", "note": $0] }, "next": NSNull()])
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
        if parts == ["rooms", "feed"], method == "GET" {
            let mine = Set(rooms.map(\.id))
            let items = posts.filter { mine.contains($0.roomId) }.sorted { $0.minutesAgo < $1.minutesAgo }.map(noteView)
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
            return json(detail(rooms[index]))
        case ("GET", ["notes"]):
            let items = posts.filter { $0.roomId == id }.sorted { $0.minutesAgo < $1.minutesAgo }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false])
        case ("POST", ["read"]):
            rooms[index].unread = 0
            return json(["unreadCount": 0])
        case ("PUT", ["feed-hidden"]), ("DELETE", ["feed-hidden"]):
            rooms[index].hiddenFromFeed = method == "PUT"
            return json(["hiddenFromFeed": rooms[index].hiddenFromFeed])
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

    private static func inviteeViews(_ id: Int64) -> [[String: Any]] {
        (invitees[id] ?? []).map {
            ["person": person($0.person), "inviterId": $0.inviter, "invitedAt": iso(minutesAgo: 10)]
        }
    }

    private static func listItem(_ room: Room) -> [String: Any] {
        let last = posts.filter { $0.roomId == room.id }.min { $0.minutesAgo < $1.minutesAgo }
        return [
            "id": room.id, "name": room.name, "memberCount": room.members.count,
            "role": room.owner ? "OWNER" : "MEMBER", "hiddenFromFeed": room.hiddenFromFeed,
            "unreadCount": room.unread,
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
            "media": [Any](), "quotedPost": NSNull(), "inReplyToId": NSNull(),
            "replyCount": 0, "repostCount": 0, "repostedByMe": false, "bookmarkedByMe": false,
            "quoteCount": 0, "linkPreview": NSNull(), "mentions": [Any](),
            "contentWarning": NSNull(), "sensitive": false, "pinned": false,
            "visibility": "room", "poll": NSNull(), "conversationMuted": false, "quotedNote": NSNull(),
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
