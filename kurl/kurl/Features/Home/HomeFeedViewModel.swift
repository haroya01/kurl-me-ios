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
    let tail: RemoteStreamModel?

    init(
        tab: HomeFeedTab,
        settled: @escaping @MainActor () -> Void = { LaunchReadiness.shared.markFirstFeedSettled() },
        remote: @escaping (RemoteStreamFeed, String?) async throws -> RemoteStreamPage = FederationAPI.stream,
        newer: @escaping (HomeFeedTab, String) async throws -> HomeFeedBatch = HomeFeedAPI.newer,
        load: @escaping (HomeFeedTab, String?) async throws -> HomeFeedBatch = HomeFeedAPI.page
    ) {
        self.tab = tab
        self.load = load
        self.newer = newer
        self.settled = settled
        self.tail = tab == .latest ? RemoteStreamModel(feed: .forYou, load: remote) : nil
    }

    var showsTail: Bool {
        guard tail != nil, case .loaded = phase else { return false }
        return next == nil
    }

    func refresh() async {
        async let remote: Void = restartTail()
        await refreshOwn()
        await remote
    }

    func reload(settlesLaunch: Bool = false) async {
        async let remote: Void = restartTail()
        await reloadOwn(settlesLaunch: settlesLaunch)
        await remote
    }

    private func restartTail() async {
        guard let tail else { return }
        if case .idle = tail.phase { return }
        await tail.reload()
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

    func inserted(_ note: Note) {
        withMotion(Motion.move) {
            phase = .loaded(true)
            items.removeAll { $0.id == HomeFeedItem(kind: .note(note)).id }
            items.insert(HomeFeedItem(kind: .note(note)), at: 0)
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
