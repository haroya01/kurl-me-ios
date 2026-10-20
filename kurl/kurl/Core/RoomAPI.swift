//
//  RoomAPI.swift
//  kurl
//

import Foundation

struct NoteRoom: Decodable, Hashable {
    let id: Int64
    let name: String
}

struct RoomPerson: Decodable, Hashable, Identifiable {
    let id: Int64
    let username: String
    let displayName: String?
    let avatarUrl: String?

    var author: Author {
        Author(id: id, username: username, bio: nil, avatarUrl: avatarUrl, displayName: displayName)
    }
}

struct RoomListItem: Decodable, Hashable, Identifiable {
    let id: Int64
    let name: String
    let memberCount: Int64
    let role: String
    let hiddenFromFeed: Bool
    let unreadCount: Int64
    let lastActivityAt: Date?
    let lastNote: LastNote?
    var faces: [RoomPerson]?
    var pinned: Bool?

    struct LastNote: Decodable, Hashable {
        let id: Int64
        let excerpt: String?
        let author: RoomPerson
        let createdAt: Date?
    }
}

struct RoomDetail: Decodable, Hashable {
    let id: Int64
    let name: String
    let role: String
    let approvalRequired: Bool
    let hiddenFromFeed: Bool
    let memberCount: Int64
    let members: [Member]

    var isOwner: Bool { role == "OWNER" }

    struct Member: Decodable, Hashable, Identifiable {
        let id: Int64
        let username: String
        let displayName: String?
        let avatarUrl: String?
        let role: String

        var author: Author {
            Author(id: id, username: username, bio: nil, avatarUrl: avatarUrl, displayName: displayName)
        }

        var person: RoomPerson {
            RoomPerson(id: id, username: username, displayName: displayName, avatarUrl: avatarUrl)
        }
    }
}

struct RoomInvite: Decodable, Hashable, Identifiable {
    let id: Int64
    let code: String
    let url: String?
    let pageUrl: String
    let maxUses: Int?
    let uses: Int
    let approval: Bool
    let expiresAt: Date?
    let disabled: Bool

    var shareURL: URL? { URL(string: url ?? pageUrl) }
}

struct RoomJoinRequest: Decodable, Hashable, Identifiable {
    let person: RoomPerson
    let requestedAt: Date?

    var id: Int64 { person.id }
}

struct RoomSuggestions: Decodable, Hashable {
    let friends: [RoomPerson]
}

struct RoomInvitee: Decodable, Hashable, Identifiable {
    let person: RoomPerson
    let inviterId: Int64
    let invitedAt: Date?

    var id: Int64 { person.id }
}

struct RoomInvitation: Decodable, Hashable, Identifiable {
    let roomId: Int64
    let roomName: String
    let memberCount: Int64
    let inviter: RoomPerson
    let approvalRequired: Bool
    let invitedAt: Date?

    var id: Int64 { roomId }
}

struct RoomJoined: Decodable, Hashable {
    let status: String
    let roomId: Int64

    var joined: Bool { status != "requested" }
}

private struct RoomName: Encodable { let name: String }
private struct RoomInviteOptions: Encodable {
    let maxUses: Int?
    let expiresInSeconds: Int64?
    let approval: Bool?
}
private struct RoomLeave: Encodable { let deleteMyNotes: Bool }
private struct RoomRead: Encodable { let noteId: Int64 }
private struct RoomDismiss: Encodable { let userIds: [Int64] }
private struct RoomInvitePeople: Encodable { let userIds: [Int64] }
private struct RoomFeedHidden: Decodable { let hiddenFromFeed: Bool }

enum RoomAPI {
    static var client = APIClient.shared

    static func mine() async throws -> [RoomListItem] {
        try await client.get("/rooms", authenticated: true)
    }

    static func create(name: String) async throws -> RoomDetail {
        try await client.post("/rooms", body: RoomName(name: name), authenticated: true)
    }

    static func detail(_ id: Int64) async throws -> RoomDetail {
        try await client.get("/rooms/\(id)", authenticated: true)
    }

    static func rename(_ id: Int64, name: String) async throws -> RoomDetail {
        try await client.patch("/rooms/\(id)", body: RoomName(name: name), authenticated: true)
    }

    static func notes(room id: Int64, page: Int) async throws -> NoteFeed {
        try await client.get(
            "/rooms/\(id)/notes", query: ["page": String(page), "size": "20"], authenticated: true)
    }

    static func feed(page: Int, size: Int = 20) async throws -> NoteFeed {
        try await client.get("/rooms/feed", query: ["page": String(page), "size": String(size)], authenticated: true)
    }

    static func read(_ id: Int64, upTo noteId: Int64) async throws {
        try await client.post("/rooms/\(id)/read", body: RoomRead(noteId: noteId), authenticated: true)
    }

    static func setHiddenFromFeed(_ id: Int64, hidden: Bool) async throws -> Bool {
        let result: RoomFeedHidden = hidden
            ? try await client.put("/rooms/\(id)/feed-hidden", authenticated: true)
            : try await client.delete("/rooms/\(id)/feed-hidden", authenticated: true)
        return result.hiddenFromFeed
    }

    static func leave(_ id: Int64, deleteMyNotes: Bool) async throws {
        try await client.post("/rooms/\(id)/leave", body: RoomLeave(deleteMyNotes: deleteMyNotes), authenticated: true)
    }

    static func remove(_ id: Int64, member memberId: Int64) async throws {
        try await client.deleteVoid("/rooms/\(id)/members/\(memberId)", authenticated: true)
    }

    static func invites(_ id: Int64) async throws -> [RoomInvite] {
        try await client.get("/rooms/\(id)/invites", authenticated: true)
    }

    static func invite(_ id: Int64, maxUses: Int? = nil, expiresIn: Int64? = nil, approval: Bool? = nil) async throws -> RoomInvite {
        try await client.post(
            "/rooms/\(id)/invites",
            body: RoomInviteOptions(maxUses: maxUses, expiresInSeconds: expiresIn, approval: approval),
            authenticated: true)
    }

    static func disable(_ id: Int64, invite inviteId: Int64) async throws -> RoomInvite {
        try await client.delete("/rooms/\(id)/invites/\(inviteId)", authenticated: true)
    }

    static func requests(_ id: Int64) async throws -> [RoomJoinRequest] {
        try await client.get("/rooms/\(id)/requests", authenticated: true)
    }

    static func approve(_ id: Int64, member memberId: Int64) async throws {
        try await client.post("/rooms/\(id)/requests/\(memberId)", body: [String: String](), authenticated: true)
    }

    static func reject(_ id: Int64, member memberId: Int64) async throws {
        try await client.deleteVoid("/rooms/\(id)/requests/\(memberId)", authenticated: true)
    }

    static func suggestions() async throws -> RoomSuggestions {
        try await client.get("/rooms/suggestions", authenticated: true)
    }

    static func dismissSuggestions(_ userIds: [Int64]) async throws {
        try await client.post("/rooms/suggestions/dismiss", body: RoomDismiss(userIds: userIds), authenticated: true)
    }

    static func pin(_ id: Int64, _ pinned: Bool) async throws {
        if pinned {
            try await client.putVoid("/rooms/\(id)/pin", authenticated: true)
        } else {
            try await client.deleteVoid("/rooms/\(id)/pin", authenticated: true)
        }
    }

    static func invitations() async throws -> [RoomInvitation] {
        try await client.get("/rooms/invitations", authenticated: true)
    }

    static func accept(_ roomId: Int64) async throws -> RoomJoined {
        try await client.post("/rooms/invitations/\(roomId)/accept", body: [String: String](), authenticated: true)
    }

    static func decline(_ roomId: Int64) async throws {
        try await client.post("/rooms/invitations/\(roomId)/decline", body: [String: String](), authenticated: true)
    }

    static func invitees(_ id: Int64) async throws -> [RoomInvitee] {
        try await client.get("/rooms/\(id)/invitations", authenticated: true)
    }

    static func invite(_ id: Int64, people userIds: [Int64]) async throws -> [RoomInvitee] {
        try await client.post("/rooms/\(id)/invitations", body: RoomInvitePeople(userIds: userIds), authenticated: true)
    }

    static func cancelInvitation(_ id: Int64, person userId: Int64) async throws {
        try await client.deleteVoid("/rooms/\(id)/invitations/\(userId)", authenticated: true)
    }
}
