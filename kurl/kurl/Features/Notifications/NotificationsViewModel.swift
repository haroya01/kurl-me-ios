import Foundation
import Observation

@MainActor
@Observable
final class NotificationsViewModel {
    var filter: NotificationFilter = .all
    var items: [AppNotification] = []
    private(set) var loading = true
    private(set) var loadingMore = false
    private(set) var loadError: String?
    private(set) var nextCursor: Int64?
    private(set) var hasMore = false
    private(set) var arrivals = Arrivals()
    private var epoch = 0
    private var catchingUp = false
    private var caughtUpAgain = false
    private var loadedAt: Date?
    static let pageSize = 20
    static let serverPageCap = 50
    static let resumeGap: TimeInterval = 5

    private let list: (Int64?, Int, NotificationFilter) async throws -> NotificationsPage
    private let now: @MainActor () -> Date
    private let companions: @MainActor () -> Void
    private let hides: @MainActor (AppNotification) -> Bool

    struct Arrivals: Equatable {
        var ids: Set<Int64> = []
        var regrouped: Set<Int64> = []
    }

    private struct Subject: Hashable {
        let type: String
        let targets: [Int64?]

        init(_ n: AppNotification) {
            type = n.type
            targets = [n.postId, n.noteId, n.commentId, n.highlightId, n.seriesId, n.collectionId]
        }
    }

    init(
        now: @escaping @MainActor () -> Date = Date.init,
        companions: @escaping @MainActor () -> Void = NotificationsViewModel.loadCompanions,
        hides: @escaping @MainActor (AppNotification) -> Bool = NotificationsViewModel.hiddenByFilter,
        list: @escaping (Int64?, Int, NotificationFilter) async throws -> NotificationsPage = {
            try await NotificationsAPI.list(before: $0, limit: $1, filter: $2)
        }
    ) {
        self.now = now
        self.companions = companions
        self.hides = hides
        self.list = list
    }

    static func loadCompanions() {
        Task { await FollowRequestStore.shared.load() }
        Task { await FilteredNotificationStore.shared.load() }
    }

    // 서버(RecordBlogNotificationUseCase.othersText)와 같은 규칙 — 남의 노트 발췌가 실린 알림만 필터가 읽는다.
    static func hiddenByFilter(_ n: AppNotification) -> Bool {
        let others: String? =
            switch n.type {
            case "NOTE_REPLY", "NOTE_QUOTE": n.sourceExcerpt
            case "NOTE_MENTION", "POST_QUOTE", "NOTE_POST", "NOTE_EDIT": n.noteExcerpt
            case "NOTE_POLL" where n.actorUsername != AuthStore.shared.me?.username: n.noteExcerpt
            default: nil
            }
        guard let others else { return false }
        return NoteFilterStore.shared.verdict(for: others, in: .notifications) == .hide
    }

    static func arrivals(from before: [AppNotification], to after: [AppNotification]) -> Arrivals {
        let known = Set(before.map(\.id))
        let fresh = after.filter { !known.contains($0.id) }
        let kept = Set(after.map(\.id))
        let gone = Set(before.filter { !kept.contains($0.id) }.map(Subject.init))
        return Arrivals(
            ids: Set(fresh.map(\.id)),
            regrouped: Set(fresh.filter { ($0.count ?? 1) > 1 && gone.contains(Subject($0)) }.map(\.id)))
    }

    func signedOut() {
        items = []
        arrivals = Arrivals()
        loadError = nil
        loading = false
        loadedAt = nil
    }

    func switchedFilter() {
        epoch += 1
        items = []
        arrivals = Arrivals()
        loadedAt = nil
        loading = true
    }

    func load() async {
        await loadFirst(size: Self.pageSize, quiet: false)
    }

    func catchUp() async {
        guard !catchingUp else {
            caughtUpAgain = true
            return
        }
        catchingUp = true
        defer { catchingUp = false }
        repeat {
            caughtUpAgain = false
            await loadFirst(size: min(max(items.count, Self.pageSize), Self.serverPageCap), quiet: true)
        } while caughtUpAgain
    }

    func resume(unread: Int64) async {
        guard unread > 0, let loadedAt, now().timeIntervalSince(loadedAt) >= Self.resumeGap else { return }
        await catchUp()
    }

    func loadMore() async {
        guard hasMore, !loadingMore, let cursor = nextCursor else { return }
        loadingMore = true
        defer { loadingMore = false }
        let myEpoch = epoch
        if let page = try? await list(cursor, Self.pageSize, filter) {
            // refresh 가 끼어들었으면 이 응답은 옛 세대 — 버린다(append 도 커서 갱신도 없음).
            guard myEpoch == epoch else { return }
            items = Self.sortedByRecency(items + page.items)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            readHidden()
        }
    }

    private func loadFirst(size: Int, quiet: Bool) async {
        companions()
        epoch += 1
        let myEpoch = epoch
        do {
            let page = try await list(nil, size, filter)
            guard myEpoch == epoch else { return }
            let before = items
            let seen = quiet && loadedAt != nil
            apply(page)
            arrive(seen ? Self.arrivals(from: before, to: items) : Arrivals())
        } catch {
            guard myEpoch == epoch else { return }
            // 실패가 빈 상태로 위장하지 않게 — 이미 보이던 목록은 보존한다.
            if items.isEmpty { loadError = error.localizedDescription }
        }
        loading = false
    }

    private func arrive(_ next: Arrivals) {
        arrivals = next
        guard !next.ids.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.arrivals == next { self?.arrivals = Arrivals() }
        }
    }

    private func apply(_ page: NotificationsPage) {
        items = Self.sortedByRecency(page.items)
        nextCursor = page.nextCursor
        hasMore = page.hasMore
        loadError = nil
        loadedAt = now()
        readHidden()
    }

    private func readHidden() {
        let ids = Set(items.filter { !$0.read && hides($0) }.map(\.id))
        guard !ids.isEmpty else { return }
        items = items.map {
            guard ids.contains($0.id) else { return $0 }
            var read = $0
            read.read = true
            return read
        }
        Task {
            for id in ids { try? await NotificationsAPI.markRead(id: id) }
            await UnreadStore.shared.refresh()
        }
    }

    /// 인박스는 항상 최신순 — 서버/목이 순서를 보장하지 않아도 클라이언트에서 createdAt 내림차순으로
    /// 못 박는다(그래프 알림이 오래된 항목 아래로 새던 것). createdAt 이 없는 항목은 뒤로 보내되
    /// 서로 간엔 원래 순서를 지킨다.
    static func sortedByRecency(_ list: [AppNotification]) -> [AppNotification] {
        list.enumerated().sorted { lhs, rhs in
            switch (lhs.element.createdAt, rhs.element.createdAt) {
            case let (l?, r?):
                if l != r { return l > r }
                return lhs.offset < rhs.offset
            case (nil, .some): return false
            case (.some, nil): return true
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
