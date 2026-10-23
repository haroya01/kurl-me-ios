import Observation
import SwiftUI

@MainActor
@Observable
final class HomeFeedViewModel {
    let tab: HomeFeedTab
    private(set) var items: [HomeFeedItem] = []
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var isLoadingMore = false
    private(set) var next: String?
    private var epoch = 0
    private(set) var newest: String?
    private let cached: (HomeFeedTab) async -> HomeFeedBatch?
    private let load: (HomeFeedTab, String?) async throws -> HomeFeedBatch
    private let newer: (HomeFeedTab, String) async throws -> HomeFeedBatch
    private let settled: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let notify: @MainActor (String) -> Void
    private let flushSeen: @MainActor () async -> Void
    private let seenBefore: @MainActor (HomeFeedItem) -> Bool
    let remote: RemoteStreamModel?
    private var leftAt: Date?

    struct PullOutcome: Equatable {
        var added = 0
        var failed = false
        var empty = false
    }

    init(
        tab: HomeFeedTab,
        settled: @escaping @MainActor () -> Void = { LaunchReadiness.shared.markFirstFeedSettled() },
        now: @escaping @MainActor () -> Date = Date.init,
        notify: @escaping @MainActor (String) -> Void = { ToastCenter.shared.show($0) },
        flushSeen: @escaping @MainActor () async -> Void = { await RemoteSeenReporter.shared.flush().value },
        seenBefore: @escaping @MainActor (HomeFeedItem) -> Bool = HomeFeedViewModel.seenBefore,
        cached: @escaping (HomeFeedTab) async -> HomeFeedBatch? = { await HomeFeedCache.shared.read($0) },
        remote: @escaping (RemoteStreamFeed, String?) async throws -> RemoteStreamPage = FederationAPI.homeStream,
        newer: @escaping (HomeFeedTab, String) async throws -> HomeFeedBatch = HomeFeedAPI.newer,
        load: @escaping (HomeFeedTab, String?) async throws -> HomeFeedBatch = HomeFeedAPI.page
    ) {
        self.tab = tab
        self.cached = cached
        self.load = load
        self.newer = newer
        self.settled = settled
        self.now = now
        self.notify = notify
        self.flushSeen = flushSeen
        self.seenBefore = seenBefore
        self.remote = tab == .latest ? RemoteStreamModel(feed: .forYou, load: remote) : nil
    }

    var rows: [HomeMix.Row] {
        guard let remote, case .loaded = phase else { return items.map { .own($0) } }
        return HomeMix.rows(own: items, remote: remote.items, ownDone: next == nil)
    }

    static func seenBefore(_ item: HomeFeedItem) -> Bool {
        leftOutOfCache(item, log: HomeSeenLog.shared, me: AuthStore.shared.me?.id)
    }

    static func leftOutOfCache(_ item: HomeFeedItem, log: HomeSeenLog, me: Int64?) -> Bool {
        log.contains(item.seenKey) && item.authorID != me
    }

    func refresh() async {
        guard tab.hidesSeen else {
            say(await refreshOwn())
            return
        }
        await flushSeen()
        say(await restart(announcesFailure: false))
    }

    func reload(settlesLaunch: Bool = false) async {
        await restart(settlesLaunch: settlesLaunch)
    }

    private func say(_ outcome: PullOutcome?) {
        guard let outcome, tab != .trending else { return }
        if case .failed = phase { return }
        guard outcome.added == 0, !outcome.empty else { return }
        notify(outcome.failed ? String(localized: "새로고침하지 못했습니다") : String(localized: "새 글이 없어요"))
    }

    @discardableResult
    private func restart(settlesLaunch: Bool = false, announcesFailure: Bool = true) async -> PullOutcome? {
        let before = Set(rows.map(\.id))
        async let theirs = reloadRemote(announcesFailure: announcesFailure)
        let mine = await reloadOwn(settlesLaunch: settlesLaunch, announcesFailure: announcesFailure)
        let theirsLoaded = await theirs
        guard let mine else { return nil }
        let after = rows
        let failed = !mine || (items.isEmpty && !theirsLoaded)
        return PullOutcome(
            added: Set(after.map(\.id)).subtracting(before).count, failed: failed, empty: !failed && after.isEmpty)
    }

    func left() {
        leftAt = now()
    }

    func returned() async {
        defer { leftAt = nil }
        guard remote != nil, HomeMix.needsReload(leftAt: leftAt, now: now()) else { return }
        await flushSeen()
        await reload()
    }

    private func reloadRemote(announcesFailure: Bool) async -> Bool {
        await remote?.reload(announcesFailure: announcesFailure) ?? true
    }

    private func refreshOwn() async -> PullOutcome? {
        guard tab != .trending, let marker = newest, !items.isEmpty else {
            let known = Set(items.map(\.id))
            guard let loaded = await reloadOwn(announcesFailure: false) else { return nil }
            return PullOutcome(added: items.filter { !known.contains($0.id) }.count, failed: !loaded)
        }
        epoch += 1
        let myEpoch = epoch
        do {
            let batch = try await newer(tab, marker)
            guard myEpoch == epoch else { return nil }
            let fresh = Self.unique(batch.items)
            let known = Set(items.map(\.id))
            let added = fresh.filter { !known.contains($0.id) }.count
            if batch.gap == true, added > 0 {
                items = fresh
                next = batch.next
            } else if !fresh.isEmpty {
                let landed = Set(fresh.map(\.id))
                withMotion(Motion.move) {
                    items = fresh + items.filter { !landed.contains($0.id) }
                }
            }
            newest = batch.newest ?? newest
            phase = .loaded(true)
            return PullOutcome(added: added)
        } catch {
            guard myEpoch == epoch else { return nil }
            return PullOutcome(failed: true)
        }
    }

    @discardableResult
    private func reloadOwn(settlesLaunch: Bool = false, announcesFailure: Bool = true) async -> Bool? {
        defer { if settlesLaunch { settled() } }
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty, let saved = await cached(tab), myEpoch == epoch, items.isEmpty {
            items = Self.unique(saved.items).filter { !tab.hidesSeen || !seenBefore($0) }
            next = saved.next
            newest = saved.newest
            phase = .loaded(true)
            if settlesLaunch { settled() }
        }
        if items.isEmpty { phase = .loading }
        do {
            let first = try await load(tab, nil)
            guard myEpoch == epoch else { return nil }
            items = Self.unique(first.items)
            next = first.next
            newest = first.newest
            phase = .loaded(true)
            return true
        } catch {
            guard myEpoch == epoch else { return nil }
            if items.isEmpty {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            } else if announcesFailure {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
            return false
        }
    }

    func loadMoreIfNeeded(current item: HomeFeedItem) async {
        guard let cursor = next, !isLoadingMore, items.suffix(5).contains(where: { $0.id == item.id }) else { return }
        isLoadingMore = true
        let myEpoch = epoch
        await Task {
            defer { isLoadingMore = false }
            guard let page = try? await load(tab, cursor), myEpoch == epoch else { return }
            next = page.next
            let seen = Set(items.map(\.id))
            items.append(contentsOf: Self.unique(page.items).filter { !seen.contains($0.id) })
        }.value
    }

    func loadMoreIfNeeded(current row: HomeMix.Row) async {
        switch row {
        case .own(let item):
            await loadMoreIfNeeded(current: item)
            await topUpRemote()
        case .remote(let item, let mixed):
            if mixed {
                await topUpRemote()
            } else {
                await remote?.loadMoreIfNeeded(current: item)
            }
        }
    }

    private func topUpRemote() async {
        guard let remote, remote.next != nil,
              HomeMix.unused(own: items, remote: remote.items) < HomeMix.lowWater else { return }
        await remote.loadMore()
    }

    func inserted(_ note: Note) {
        let item = HomeFeedItem(kind: .note(note))
        withMotion(Motion.move) {
            phase = .loaded(true)
            items.removeAll { $0.id == item.id }
            items.insert(item, at: 0)
        }
    }

    func replaced(_ note: Note) {
        guard let index = items.firstIndex(where: { $0.note?.id == note.id }), let old = items[index].note else { return }
        var next = note
        next.repostedBy = next.repostedBy ?? old.repostedBy
        items[index] = HomeFeedItem(kind: .note(next))
    }

    func removed(_ id: Int64) {
        HomeFeedCache.shared.wipe()
        withMotion(Motion.move) { items.removeAll { $0.note?.id == id } }
    }

    static func unique(_ items: [HomeFeedItem]) -> [HomeFeedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
