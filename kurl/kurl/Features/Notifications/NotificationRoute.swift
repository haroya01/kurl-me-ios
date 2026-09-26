import Foundation

enum NotificationRoute {
    static func route(
        actorUsername: String?,
        ownerUsername: String?,
        postSlug: String?,
        seriesSlug: String?,
        collectionId: Int64?
    ) -> Route? {
        if let collectionId {
            return .collection(id: collectionId)
        }
        if let slug = filled(postSlug), let owner = filled(ownerUsername) {
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
            collectionId: n.collectionId)
    }

    static func route(push userInfo: [AnyHashable: Any]) -> Route? {
        route(
            actorUsername: userInfo["actorUsername"] as? String,
            ownerUsername: userInfo["ownerUsername"] as? String,
            postSlug: userInfo["postSlug"] as? String,
            seriesSlug: userInfo["seriesSlug"] as? String,
            collectionId: (userInfo["collectionId"] as? NSNumber)?.int64Value)
    }

    private static func filled(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
