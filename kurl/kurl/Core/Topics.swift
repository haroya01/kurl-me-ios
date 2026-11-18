import Foundation

struct TopicArticle: Decodable, Hashable {
    let url: String
    let title: String?
    let source: String?

    var shownTitle: String {
        if let title, !title.isEmpty { return title }
        return url
    }

    var link: URL? {
        URL(string: url).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
    }
}

struct Topic: Hashable, Identifiable {
    enum Subject: Hashable {
        case tag(String)
        case link(url: String, title: String?, source: String?)
    }

    let id: String
    let subject: Subject
    let language: String?
    let own: Bool
    let people: Int
    let related: [TopicArticle]

    var route: Route {
        switch subject {
        case .tag(let name): .noteTag(name)
        case .link(let url, let title, _): .noteLink(url: url, title: title)
        }
    }

    var title: String {
        switch subject {
        case .tag(let name): return "#\(name)"
        case .link(let url, let title, _):
            if let title, !title.isEmpty { return title }
            return url
        }
    }

    func meta(locale: Locale = .current) -> String? {
        var parts: [String] = []
        if case .link(let url, _, let source) = subject {
            if let source, !source.isEmpty {
                parts.append(source)
            } else if let host = Self.host(of: url) {
                parts.append(host)
            }
        }
        if !own, let language, let name = locale.localizedString(forLanguageCode: language) {
            parts.append(name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func host(of url: String) -> String? {
        guard let host = URL(string: url)?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

extension Topic: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, tag, url, title, source, language, own, people, related
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "tag":
            subject = .tag(try container.decode(String.self, forKey: .tag))
        case "link":
            subject = .link(
                url: try container.decode(String.self, forKey: .url),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                source: try container.decodeIfPresent(String.self, forKey: .source))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "unknown topic kind")
        }
        id = try container.decode(String.self, forKey: .id)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        own = try container.decode(Bool.self, forKey: .own)
        people = try container.decode(Int.self, forKey: .people)
        related = try container.decodeIfPresent([TopicArticle].self, forKey: .related) ?? []
    }
}

struct TopicList: Decodable {
    let items: [Topic]

    private enum CodingKeys: String, CodingKey { case items }

    private struct Slot: Decodable {
        let topic: Topic?

        init(from decoder: Decoder) throws {
            topic = try? Topic(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([Slot].self, forKey: .items).compactMap(\.topic)
    }
}

enum TopicKey: Hashable {
    case tag(String)
    case link(String)
}

struct TopicPostsPage: Decodable {
    let topic: Topic?
    let items: [RemoteStreamItem]
    let next: String?

    private enum CodingKeys: String, CodingKey { case topic, items, next }

    init(topic: Topic?, items: [RemoteStreamItem], next: String?) {
        self.topic = topic
        self.items = items
        self.next = next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topic = (try? container.decodeIfPresent(Topic.self, forKey: .topic)) ?? nil
        items = try container.decode([RemoteStreamItem].self, forKey: .items)
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }
}

struct TopicBoard: Equatable {
    struct Row: Identifiable, Equatable {
        let rank: Int
        let topic: Topic

        var id: String { topic.id }
    }

    static let laneCap = 10
    static let chipCap = 5

    let own: [Row]
    let others: [Row]
    let hasMore: Bool

    init(_ topics: [Topic], cap: Int? = nil) {
        var seen = Set<String>()
        let unique = topics.filter { seen.insert($0.id).inserted }
        let ordered = unique.filter(\.own) + unique.filter { !$0.own }
        let shown = cap.map { Array(ordered.prefix($0)) } ?? ordered
        let rows = shown.enumerated().map { Row(rank: $0.offset + 1, topic: $0.element) }
        own = rows.filter(\.topic.own)
        others = rows.filter { !$0.topic.own }
        hasMore = shown.count < ordered.count
    }

    var isEmpty: Bool { own.isEmpty && others.isEmpty }

    var headsOthers: Bool { !own.isEmpty && !others.isEmpty }

    static func chipTags(_ topics: [Topic], limit: Int = chipCap) -> [String] {
        var seen = Set<String>()
        let ordered = topics.filter(\.own) + topics.filter { !$0.own }
        let names = ordered.compactMap { topic -> String? in
            guard case .tag(let name) = topic.subject, seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
        return Array(names.prefix(limit))
    }
}

extension FederationAPI {
    static let topicLimit = 20
    static let topicListLimit = 40

    static func topics(limit: Int) async throws -> [Topic] {
        let page: TopicList = try await client.getAsViewer("/federation/topics", query: ["limit": String(limit)])
        return page.items
    }

    static func topicPosts(_ key: TopicKey, cursor: String?) async throws -> TopicPostsPage {
        var query: [String: String?] = ["limit": String(trendingLimit), "cursor": cursor]
        switch key {
        case .tag(let name): query["tag"] = name
        case .link(let url): query["url"] = url
        }
        return try await client.getAsViewer("/federation/topics/posts", query: query)
    }
}
