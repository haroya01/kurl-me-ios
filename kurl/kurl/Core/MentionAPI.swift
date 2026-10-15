import Foundation

struct MentionCandidate: Decodable, Identifiable, Hashable {
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let following: Bool

    var id: String { username }
}

enum MentionAPI {
    private static let client = APIClient.shared

    static func candidates(_ query: String, limit: Int = 6) async throws -> [MentionCandidate] {
        try await client.get(
            "/users/me/mention-candidates",
            query: ["q": query, "limit": String(limit)],
            authenticated: true)
    }
}

/// 본문 끝에서 치고 있는 "@이름" — TextField 는 커서 위치를 주지 않아 끝에서만 찾는다.
enum MentionDraft {
    private static let pattern = try? NSRegularExpression(
        pattern: "(?:^|[\\s(\\[{\"'“‘])@([\\p{L}\\p{N}_]{0,30})$")
    private static let serverPattern = try? NSRegularExpression(
        pattern: "(?:^|[\\s(\\[{\"'“‘])@([\\p{L}\\p{N}_]{0,30}(?:@[A-Za-z0-9.\\-]{0,253})?)$")

    static func trailingQuery(in text: String, allowingServer: Bool = false) -> String? {
        let ns = text as NSString
        let regex = allowingServer ? serverPattern : pattern
        guard let match = regex?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    static func complete(_ text: String, with handle: String, allowingServer: Bool = false) -> String {
        guard let query = trailingQuery(in: text, allowingServer: allowingServer) else { return text }
        return String(text.dropLast(query.count + 1)) + "@\(handle) "
    }
}
