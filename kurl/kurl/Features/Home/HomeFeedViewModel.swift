//
//  HomeFeedViewModel.swift
//  kurl
//

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
    private let load: (HomeFeedTab, String?) async throws -> HomeFeedBatch

    init(tab: HomeFeedTab, load: @escaping (HomeFeedTab, String?) async throws -> HomeFeedBatch = HomeFeedAPI.page) {
        self.tab = tab
        self.load = load
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty { phase = .loading }
        do {
            let first = try await load(tab, nil)
            guard myEpoch == epoch else { return }
            items = Self.unique(first.items)
            next = first.next
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
        guard let cursor = next, !isLoadingMore, items.last?.id == item.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let myEpoch = epoch
        guard let page = try? await load(tab, cursor), myEpoch == epoch else { return }
        next = page.next
        let seen = Set(items.map(\.id))
        items.append(contentsOf: Self.unique(page.items).filter { !seen.contains($0.id) })
    }

    func inserted(_ note: Note) {
        withAnimation(.snappy(duration: 0.3)) {
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
        withAnimation(.snappy(duration: 0.25)) { items.removeAll { $0.note?.id == id } }
    }

    static func unique(_ items: [HomeFeedItem]) -> [HomeFeedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
