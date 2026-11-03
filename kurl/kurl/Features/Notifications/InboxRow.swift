import Foundation

struct InboxRow: Equatable {
    enum Kind: Equatable {
        case like, highlight, quote, comment, reply, follow, followRequest, subscribe, newPost, mention, repost
        case pollEnded, newNote, edit, firstReader, other
        case connected(String)
        case pathGrew(String)
        case readMilestone(Int?)
    }

    enum Mine: Equatable {
        case post, note, comment, highlightReply, series, poll
    }

    enum Detail: Equatable {
        case theirs(String)
        case mine(Mine, String)
    }

    let name: String?
    let others: Int
    let kind: Kind
    let detail: Detail?
    let symbol: String

    init(_ n: AppNotification, me: String?) {
        let mine = n.actorUsername != nil && n.actorUsername == me
        let collection = n.collectionName ?? String(localized: "컬렉션")
        let kind: Kind
        let detail: Detail?
        switch n.type {
        case "LIKE":
            (kind, detail) = (.like, Self.mine(.post, n.postTitle))
        case "COMMENT_LIKE":
            let reply = n.commentId == nil && n.highlightId != nil
            (kind, detail) = (.like, Self.mine(reply ? .highlightReply : .comment, n.postTitle))
        case "HIGHLIGHT":
            (kind, detail) = (.highlight, Self.mine(.post, n.postTitle))
        case "POST_QUOTE":
            (kind, detail) = (.quote, Self.theirs(n.noteExcerpt))
        case "NOTE_EMBED":
            (kind, detail) = (.quote, Self.theirs(n.postTitle))
        case "COMMENT":
            (kind, detail) = (.comment, Self.mine(.post, n.postTitle))
        case "REPLY":
            (kind, detail) = (.reply, Self.mine(.comment, n.postTitle))
        case "FOLLOW", "REMOTE_FOLLOW":
            (kind, detail) = (.follow, nil)
        case "FOLLOW_REQUEST":
            (kind, detail) = (.followRequest, nil)
        case "SERIES_SUBSCRIBE":
            (kind, detail) = (.subscribe, Self.mine(.series, n.seriesTitle))
        case "NEW_POST":
            (kind, detail) = (.newPost, Self.theirs(n.postTitle))
        case "MENTION":
            (kind, detail) = (.mention, Self.theirs(n.postTitle))
        case "CONNECTED":
            (kind, detail) = (.connected(collection), Self.mine(.post, n.postTitle))
        case "PATH_GREW":
            (kind, detail) = (.pathGrew(collection), Self.theirs(n.postTitle))
        case "NOTE_LIKE":
            (kind, detail) = (.like, Self.mine(.note, n.noteExcerpt))
        case "NOTE_REPOST":
            (kind, detail) = (.repost, Self.mine(.note, n.noteExcerpt))
        case "NOTE_REPLY":
            (kind, detail) = (.reply, Self.theirs(n.sourceExcerpt))
        case "NOTE_QUOTE":
            (kind, detail) = (.quote, Self.theirs(n.sourceExcerpt))
        case "NOTE_MENTION":
            (kind, detail) = (.mention, Self.theirs(n.noteExcerpt))
        case "NOTE_POLL":
            (kind, detail) = (.pollEnded, mine ? Self.mine(.poll, n.noteExcerpt) : Self.theirs(n.noteExcerpt))
        case "NOTE_POST":
            (kind, detail) = (.newNote, Self.theirs(n.noteExcerpt))
        case "NOTE_EDIT":
            (kind, detail) = (.edit, Self.theirs(n.noteExcerpt))
        case "POST_FIRST_READER":
            (kind, detail) = (.firstReader, Self.mine(.post, n.postTitle))
        case "POST_READ_MILESTONE":
            (kind, detail) = (.readMilestone(n.milestone), Self.mine(.post, n.postTitle))
        default:
            (kind, detail) = (.other, Self.theirs(n.postTitle ?? n.seriesTitle))
        }
        let actorless: Bool =
            switch kind {
            case .firstReader, .readMilestone: true
            default: mine
            }
        self.name = actorless ? nil : Self.name(display: n.actorDisplayName, username: n.actorUsername)
        self.others = max((n.count ?? 1) - 1, 0)
        self.kind = kind
        self.detail = detail
        self.symbol = Self.symbol(n.type)
    }

    static func name(display: String?, username: String?) -> String? {
        if let display = display?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        return displayName(username)
    }

    static func displayName(_ username: String?) -> String? {
        guard let username else { return nil }
        let bare = username.hasPrefix("@") ? String(username.dropFirst()) : username
        let local = bare.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        return local.isEmpty ? nil : local
    }

    private static func theirs(_ text: String?) -> Detail? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return .theirs(text)
    }

    private static func mine(_ target: Mine, _ text: String?) -> Detail? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return .mine(target, text)
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case "LIKE", "COMMENT_LIKE", "NOTE_LIKE": "heart.fill"
        case "COMMENT": "bubble.left.fill"
        case "REPLY", "NOTE_REPLY": "arrowshape.turn.up.left.fill"
        case "FOLLOW", "REMOTE_FOLLOW": "person.fill.badge.plus"
        case "SERIES_SUBSCRIBE": "books.vertical.fill"
        case "NEW_POST": "doc.text.fill"
        case "MENTION", "NOTE_MENTION": "at"
        case "HIGHLIGHT": "highlighter"
        case "POST_QUOTE", "NOTE_EMBED", "NOTE_QUOTE": "quote.bubble.fill"
        case "CONNECTED": "link"
        case "PATH_GREW": "arrow.triangle.branch"
        case "NOTE_REPOST": "arrow.2.squarepath"
        case "NOTE_POLL": "chart.bar.xaxis"
        case "NOTE_EDIT": "pencil"
        case "FOLLOW_REQUEST": "person.badge.clock"
        case "POST_FIRST_READER", "POST_READ_MILESTONE": "person.fill"
        default: "bell.fill"
        }
    }
}

extension InboxRow.Kind {
    var label: LocalizedStringResource? {
        switch self {
        case .like: LocalizedStringResource("inbox.kind.like", defaultValue: "좋아요")
        case .highlight: LocalizedStringResource("inbox.kind.highlight", defaultValue: "하이라이트")
        case .quote: LocalizedStringResource("inbox.kind.quote", defaultValue: "인용")
        case .comment: LocalizedStringResource("inbox.kind.comment", defaultValue: "댓글")
        case .reply: LocalizedStringResource("inbox.kind.reply", defaultValue: "답글")
        case .follow: LocalizedStringResource("inbox.kind.follow", defaultValue: "팔로우")
        case .followRequest: LocalizedStringResource("inbox.kind.followRequest", defaultValue: "팔로우 요청")
        case .subscribe: LocalizedStringResource("inbox.kind.subscribe", defaultValue: "시리즈 구독")
        case .newPost: LocalizedStringResource("inbox.kind.newPost", defaultValue: "새 글")
        case .mention: LocalizedStringResource("inbox.kind.mention", defaultValue: "언급")
        case .repost: LocalizedStringResource("inbox.kind.repost", defaultValue: "리포스트")
        case .pollEnded: LocalizedStringResource("inbox.kind.pollEnded", defaultValue: "투표 마감")
        case .newNote: LocalizedStringResource("inbox.kind.newNote", defaultValue: "새 노트")
        case .edit: LocalizedStringResource("inbox.kind.edit", defaultValue: "수정")
        case .firstReader: LocalizedStringResource("inbox.kind.firstReader", defaultValue: "첫 독자")
        case .connected(let name):
            LocalizedStringResource("inbox.kind.connected", defaultValue: "‘\(name)’에 엮음")
        case .pathGrew(let name):
            LocalizedStringResource("inbox.kind.pathGrew", defaultValue: "‘\(name)’에 새 글")
        case .readMilestone(let count?):
            LocalizedStringResource("inbox.kind.readers", defaultValue: "\(count)명이 읽음")
        case .readMilestone(nil): LocalizedStringResource("읽은 사람이 늘었어요")
        case .other: nil
        }
    }
}

extension InboxRow.Mine {
    var label: LocalizedStringResource {
        switch self {
        case .post: LocalizedStringResource("inbox.mine.post", defaultValue: "내 글")
        case .note: LocalizedStringResource("inbox.mine.note", defaultValue: "내 노트")
        case .comment: LocalizedStringResource("inbox.mine.comment", defaultValue: "내 댓글")
        case .highlightReply: LocalizedStringResource("inbox.mine.highlightReply", defaultValue: "하이라이트에 단 내 답글")
        case .series: LocalizedStringResource("inbox.mine.series", defaultValue: "내 시리즈")
        case .poll: LocalizedStringResource("inbox.mine.poll", defaultValue: "내 투표")
        }
    }
}

enum InboxSection: Hashable, CaseIterable {
    case today, thisWeek, earlier

    var title: LocalizedStringResource {
        switch self {
        case .today: "오늘"
        case .thisWeek: "이번 주"
        case .earlier: "이전"
        }
    }

    struct Bucket: Identifiable {
        let section: InboxSection
        let items: [AppNotification]
        var id: InboxSection { section }
    }

    static func buckets(_ items: [AppNotification], now: Date, calendar: Calendar) -> [Bucket] {
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        var grouped: [InboxSection: [AppNotification]] = [:]
        for item in items {
            let section: InboxSection =
                switch item.createdAt {
                case let date? where date >= dayStart: .today
                case let date? where date >= weekStart: .thisWeek
                default: .earlier
                }
            grouped[section, default: []].append(item)
        }
        return allCases.compactMap { section in
            grouped[section].map { Bucket(section: section, items: $0) }
        }
    }
}
