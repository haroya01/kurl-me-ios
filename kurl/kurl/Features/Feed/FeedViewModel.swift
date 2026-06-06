//
//  FeedViewModel.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class FeedViewModel {
    let sort: FeedSort

    private(set) var items: [FeedItem] = []
    private(set) var phase: LoadState<[FeedItem]> = .idle
    private(set) var isLoadingMore = false

    private var page = 0
    private var hasNext = true
    private let pageSize = 20

    init(sort: FeedSort) {
        self.sort = sort
    }

    func loadInitial() async {
        guard case .idle = phase else { return }
        await reload()
    }

    func reload() async {
        page = 0
        hasNext = true
        if items.isEmpty { phase = .loading }
        do {
            let view = try await BlogAPI.feed(sort: sort, page: 0, size: pageSize)
            hasNext = view.hasNext
            withAnimation(.easeInOut(duration: 0.2)) {
                items = view.items
                phase = .loaded(items)
            }
        } catch {
            if items.isEmpty {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    func loadMoreIfNeeded(current item: FeedItem) async {
        guard hasNext, !isLoadingMore else { return }
        guard let last = items.last, last.id == item.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        do {
            let view = try await BlogAPI.feed(sort: sort, page: page, size: pageSize)
            items.append(contentsOf: view.items)
            hasNext = view.hasNext
            phase = .loaded(items)
        } catch {
            page -= 1
        }
    }
}
