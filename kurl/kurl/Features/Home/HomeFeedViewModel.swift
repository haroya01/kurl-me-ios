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
    let remote: RemoteStreamModel?
    private(set) var top: [HomeMix.Slot] = []
    private var pulledAt: Date?
    private var leftAt: Date?

    struct PullOutcome: Equatable {
        var added = 0
        var failed = false
    }

    init(
        tab: HomeFeedTab,
        settled: @escaping @MainActor () -> Void = { LaunchReadiness.shared.markFirstFeedSettled() },
        now: @escaping @MainActor () -> Date = Date.init,
        notify: @escaping @MainActor (String) -> Void = { ToastCenter.shared.show($0) },
        cached: @escaping (HomeFeedTab) async -> HomeFeedBatch? = { await HomeFeedCache.shared.read($0) },
        remote: @escaping (RemoteStreamFeed, String?) async throws -> RemoteStreamPage = FederationAPI.stream,
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
        self.remote = tab == .latest ? RemoteStreamModel(feed: .forYou, load: remote) : nil
    }

    var rows: [HomeMix.Row] {
        guard let remote, case .loaded = phase else { return items.map { .own($0) } }
        return HomeMix.rows(own: items, remote: remote.items, ownDone: next == nil, top: top)
    }

    func refresh() async {
        let outcome: PullOutcome?
        if let remote, case .loaded = remote.phase, let since = pulledAt, let marker = newest, !items.isEmpty {
            outcome = await pull(remote, since: since, marker: marker)
        } else if let remote {
            pulledAt = now()
            let before = remote.items.count
            async let other: Void = remote.reload()
            var own = await refreshOwn()
            await other
            if before == 0 { own?.added += remote.items.count }
            outcome = own
        } else {
            outcome = await refreshOwn()
        }
        guard let outcome, tab != .trending else { return }
        if case .failed = phase { return }
        guard outcome.added == 0 else { return }
        notify(outcome.failed ? String(localized: "새로고침하지 못했습니다") : String(localized: "새 글이 없어요"))
    }

    func reload(settlesLaunch: Bool = false) async {
        top = []
        pulledAt = now()
        async let other: Void = reloadRemote()
        await reloadOwn(settlesLaunch: settlesLaunch)
        await other
    }

    func left() {
        leftAt = now()
    }

    func returned() async {
        defer { leftAt = nil }
        guard remote != nil, HomeMix.needsReload(leftAt: leftAt, now: now()) else { return }
        await reload()
    }

    private func reloadRemote() async {
        await remote?.reload()
    }

    private func pull(_ remote: RemoteStreamModel, since: Date, marker: String) async -> PullOutcome? {
        epoch += 1
        let myEpoch = epoch
        let started = now()
        async let theirs = try? remote.fresh(since: since)
        let batch: HomeFeedBatch?
        do {
            batch = try await newer(tab, marker)
        } catch {
            batch = nil
        }
        let fresh = await theirs
        guard myEpoch == epoch else { return nil }
        if fresh != nil { pulledAt = started }
        let added = fresh ?? []
        guard let batch else {
            withMotion(Motion.move) {
                remote.prepend(added)
                top = HomeMix.block(own: [], remote: added) + top
            }
            return PullOutcome(added: added.count, failed: true)
        }
        let incoming = Self.unique(batch.items)
        let known = Set(items.map(\.id))
        let mine = incoming.filter { !known.contains($0.id) }
        if batch.gap == true, !mine.isEmpty {
            withMotion(Motion.move) {
                items = incoming
                next = batch.next
                remote.prepend(added)
                top = HomeMix.block(own: [], remote: added)
            }
        } else {
            let updates = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            withMotion(Motion.move) {
                items = mine + items.map { updates[$0.id] ?? $0 }
                remote.prepend(added)
                top = HomeMix.block(own: mine, remote: added) + top
            }
        }
        newest = batch.newest ?? newest
        phase = .loaded(true)
        return PullOutcome(added: mine.count + added.count)
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
            items = Self.unique(saved.items)
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
            top.insert(.own(item.id), at: 0)
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
