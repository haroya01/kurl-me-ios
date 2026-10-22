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
    private let load: (HomeFeedTab, String?) async throws -> HomeFeedBatch
    private let newer: (HomeFeedTab, String) async throws -> HomeFeedBatch
    private let settled: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let notify: @MainActor (String) -> Void
    let remote: RemoteStreamModel?
    private(set) var top: [HomeMix.Slot] = []
    private var pulledAt: Date?
    private var leftAt: Date?

    init(
        tab: HomeFeedTab,
        settled: @escaping @MainActor () -> Void = { LaunchReadiness.shared.markFirstFeedSettled() },
        now: @escaping @MainActor () -> Date = Date.init,
        notify: @escaping @MainActor (String) -> Void = { ToastCenter.shared.show($0) },
        remote: @escaping (RemoteStreamFeed, String?) async throws -> RemoteStreamPage = FederationAPI.stream,
        newer: @escaping (HomeFeedTab, String) async throws -> HomeFeedBatch = HomeFeedAPI.newer,
        load: @escaping (HomeFeedTab, String?) async throws -> HomeFeedBatch = HomeFeedAPI.page
    ) {
        self.tab = tab
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
        guard let remote else {
            await refreshOwn()
            return
        }
        guard case .loaded = remote.phase, let since = pulledAt, let marker = newest, !items.isEmpty else {
            pulledAt = now()
            async let other: Void = remote.reload()
            await refreshOwn()
            await other
            return
        }
        await pull(remote, since: since, marker: marker)
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

    private func pull(_ remote: RemoteStreamModel, since: Date, marker: String) async {
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
        guard myEpoch == epoch else { return }
        if fresh != nil { pulledAt = started }
        let added = fresh ?? []
        guard let batch else {
            withMotion(Motion.move) {
                remote.prepend(added)
                top = HomeMix.block(own: [], remote: added) + top
            }
            notify(String(localized: "새로고침하지 못했습니다"))
            return
        }
        if batch.gap == true {
            items = Self.unique(batch.items)
            next = batch.next
            remote.prepend(added)
            top = HomeMix.block(own: [], remote: added)
        } else {
            let incoming = Self.unique(batch.items)
            let known = Set(items.map(\.id))
            let updates = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let mine = incoming.filter { !known.contains($0.id) }
            withMotion(Motion.move) {
                items = mine + items.map { updates[$0.id] ?? $0 }
                remote.prepend(added)
                top = HomeMix.block(own: mine, remote: added) + top
            }
            if mine.isEmpty, fresh?.isEmpty == true { notify(String(localized: "새 글이 없어요")) }
        }
        newest = batch.newest ?? newest
        phase = .loaded(true)
    }

    private func refreshOwn() async {
        guard tab != .trending, let marker = newest, !items.isEmpty else {
            await reloadOwn()
            return
        }
        epoch += 1
        let myEpoch = epoch
        do {
            let batch = try await newer(tab, marker)
            guard myEpoch == epoch else { return }
            if batch.gap == true {
                items = Self.unique(batch.items)
                next = batch.next
            } else if !batch.items.isEmpty {
                let fresh = Self.unique(batch.items)
                let known = Set(fresh.map(\.id))
                withMotion(Motion.move) {
                    items = fresh + items.filter { !known.contains($0.id) }
                }
            }
            newest = batch.newest ?? newest
            phase = .loaded(true)
        } catch {
            guard myEpoch == epoch else { return }
            ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
        }
    }

    private func reloadOwn(settlesLaunch: Bool = false) async {
        defer { if settlesLaunch { settled() } }
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty { phase = .loading }
        do {
            let first = try await load(tab, nil)
            guard myEpoch == epoch else { return }
            items = Self.unique(first.items)
            next = first.next
            newest = first.newest
            phase = .loaded(true)
        } catch {
            guard myEpoch == epoch else { return }
            if items.isEmpty {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            } else {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
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
        withMotion(Motion.move) { items.removeAll { $0.note?.id == id } }
    }

    static func unique(_ items: [HomeFeedItem]) -> [HomeFeedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
