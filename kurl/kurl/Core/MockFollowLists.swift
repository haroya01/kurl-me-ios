import Foundation

#if DEBUG
@MainActor
enum MockFollowLists {
    private static let remoteFollowerIds: [Int64] = [9810, 9840]

    private static var remoteFollowing: [[String: Any]] {
        MockBackend.remoteAccounts.values
            .filter { ($0["following"] as? Bool) == true }
            .sorted { (($0["id"] as? Int64) ?? 0) < (($1["id"] as? Int64) ?? 0) }
    }

    private static var remoteFollowers: [[String: Any]] {
        remoteFollowerIds.compactMap { MockBackend.remoteAccounts[$0] }
    }

    static func counts(username: String, me: String) -> [String: Any] {
        guard username == me else { return [:] }
        return [
            "remoteFollowerCount": Int64(remoteFollowers.count),
            "remoteFollowingCount": Int64(remoteFollowing.count),
        ]
    }

    static func respond(parts: [String], method: String, query: [URLQueryItem]?, body: Data?) -> Data? {
        guard method == "GET", parts.count == 3, parts[0] == "users",
              parts[2] == "followers" || parts[2] == "following",
              query?.contains(where: { $0.name == "include" && $0.value == "remote" }) == true,
              let base = MockRooms.respond(parts: parts, method: method, body: body),
              var page = try? JSONSerialization.jsonObject(with: base) as? [String: Any],
              let locals = page["items"] as? [[String: Any]]
        else { return nil }
        var items: [[String: Any]] = locals.map { $0.merging(["type": "local"]) { _, new in new } }
        let remotes = parts[2] == "followers" ? remoteFollowers : remoteFollowing
        for (index, account) in remotes.enumerated() {
            items.insert(["type": "remote", "account": account], at: min(1 + index * 2, items.count))
        }
        page["items"] = items
        return try? JSONSerialization.data(withJSONObject: page)
    }
}
#endif
