import Foundation
import Observation

@MainActor
@Observable
final class PostAccess {
    static let shared = PostAccess()

    struct Credential: Equatable {
        var key: String?
        var grant: String?
    }

    private var credentials: [String: Credential] = [:]
    private var addressById: [Int64: String] = [:]
    private var postByHighlight: [Int64: Int64] = [:]
    private var postByComment: [Int64: Int64] = [:]
    private var postByReply: [Int64: Int64] = [:]
    private(set) var lockouts: [String: Int] = [:]

    init() {
        #if DEBUG
        if let link = Config.launchValue(after: "--post").flatMap(PostLink.init(target:)), let key = link.key {
            credentials[Self.address(username: link.username, slug: link.slug)] = Credential(key: key)
        }
        #endif
    }

    static func address(username: String, slug: String) -> String { "\(username)/\(slug)" }

    func credential(username: String, slug: String) -> Credential? {
        credentials[Self.address(username: username, slug: slug)]
    }

    func hasGrant(username: String, slug: String) -> Bool {
        credential(username: username, slug: slug)?.grant != nil
    }

    func setKey(_ key: String, username: String, slug: String) {
        credentials[Self.address(username: username, slug: slug), default: Credential()].key = key
    }

    func setGrant(_ grant: String, username: String, slug: String) {
        credentials[Self.address(username: username, slug: slug), default: Credential()].grant = grant
    }

    func dropGrant(username: String, slug: String) {
        let address = Self.address(username: username, slug: slug)
        credentials[address]?.grant = nil
    }

    func bind(postId: Int64, username: String, slug: String) {
        addressById[postId] = Self.address(username: username, slug: slug)
    }

    func link(highlights ids: [Int64], to postId: Int64) {
        for id in ids { postByHighlight[id] = postId }
    }

    func link(comments ids: [Int64], to postId: Int64) {
        for id in ids { postByComment[id] = postId }
    }

    func link(replies ids: [Int64], ofHighlight highlightId: Int64) {
        guard let postId = postByHighlight[highlightId] else { return }
        for id in ids { postByReply[id] = postId }
    }

    func reset() {
        credentials = [:]
        addressById = [:]
        postByHighlight = [:]
        postByComment = [:]
        postByReply = [:]
        lockouts = [:]
    }

    func headers(forPath path: String) -> [String: String] {
        guard let address = address(forPath: path), let credential = credentials[address] else { return [:] }
        var headers: [String: String] = [:]
        if let key = credential.key { headers["X-Post-Key"] = key }
        if let grant = credential.grant { headers["X-Post-Grant"] = grant }
        return headers
    }

    func lockedOut(path: String) {
        guard let address = address(forPath: path), credentials[address]?.grant != nil else { return }
        credentials[address]?.grant = nil
        lockouts[address, default: 0] += 1
    }

    private func address(forPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        var rest = parts[...]
        if rest.first == "public" { rest = rest.dropFirst() }
        guard rest.count >= 2 else { return nil }
        let head = rest[rest.startIndex]
        let second = rest[rest.startIndex + 1]
        switch head {
        case "profiles":
            guard rest.count >= 4, rest[rest.startIndex + 2] == "posts" else { return nil }
            return Self.address(username: second, slug: rest[rest.startIndex + 3])
        case "posts":
            return Int64(second).flatMap { addressById[$0] }
        case "highlights":
            return Int64(second).flatMap { postByHighlight[$0] }.flatMap { addressById[$0] }
        case "comments":
            return Int64(second).flatMap { postByComment[$0] }.flatMap { addressById[$0] }
        case "highlight-replies":
            return Int64(second).flatMap { postByReply[$0] }.flatMap { addressById[$0] }
        default:
            return nil
        }
    }
}
