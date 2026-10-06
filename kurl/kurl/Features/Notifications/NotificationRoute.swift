import Foundation

enum NotificationRoute {
    static func route(
        actorUsername: String?,
        ownerUsername: String?,
        postSlug: String?,
        seriesSlug: String?,
        collectionId: Int64?,
        commentId: Int64? = nil,
        highlightId: Int64? = nil,
        noteId: Int64? = nil
    ) -> Route? {
        if let collectionId {
            return .collection(id: collectionId)
        }
        if let noteId {
            return .note(id: noteId)
        }
        if let slug = filled(postSlug), let owner = filled(ownerUsername) {
            if let commentId {
                return .postSpot(username: owner, slug: slug, spot: .comment(commentId))
            }
            if let highlightId {
                return .postSpot(username: owner, slug: slug, spot: .highlight(highlightId))
            }
            return .post(username: owner, slug: slug)
        }
        if let slug = filled(seriesSlug), let owner = filled(ownerUsername) {
            return .series(username: owner, slug: slug)
        }
        if let actor = filled(actorUsername) {
            return .author(username: actor)
        }
        return nil
    }

    @MainActor
    static func route(for n: AppNotification) -> Route? {
        switch n.type {
        case "NOTE_LIKE", "NOTE_REPOST": return n.noteId.map { .note(id: $0) }
        case "NOTE_REPLY", "NOTE_QUOTE": return n.sourceNoteId.map { .note(id: $0) }
        case "REMOTE_FOLLOW": return nil
        default: break
        }
        let mine = AuthStore.shared.me?.username
        let owner =
            n.postSlug == nil
            ? mine
            : filled(n.postAuthorUsername)
                ?? (n.type == "NEW_POST" ? filled(n.actorUsername) : nil)
                ?? mine
        return route(
            actorUsername: n.actorUsername,
            ownerUsername: owner,
            postSlug: n.postSlug,
            seriesSlug: n.seriesSlug,
            collectionId: n.collectionId,
            commentId: n.commentId,
            highlightId: n.highlightId)
    }

    static func route(push userInfo: [AnyHashable: Any]) -> Route? {
        route(
            actorUsername: userInfo["actorUsername"] as? String,
            ownerUsername: userInfo["ownerUsername"] as? String,
            postSlug: userInfo["postSlug"] as? String,
            seriesSlug: userInfo["seriesSlug"] as? String,
            collectionId: (userInfo["collectionId"] as? NSNumber)?.int64Value,
            commentId: (userInfo["commentId"] as? NSNumber)?.int64Value,
            highlightId: (userInfo["highlightId"] as? NSNumber)?.int64Value,
            noteId: (userInfo["noteId"] as? NSNumber)?.int64Value)
    }

    private static func filled(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
