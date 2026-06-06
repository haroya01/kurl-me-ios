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
    var sort: FeedSort = .recent {
        didSet { if oldValue != sort { Task { await reload() } } }
    }

    private(set) var items: [FeedItem] = []
    private(set) var phase: LoadState<[FeedItem]> = .idle
    private(set) var isLoadingMore = false

    private var page = 0
    private var hasNext = true
    private let pageSize = 20

    func loadInitial() async {
        guard case .idle = phase else { return }
        await reload()
    }

    func reload() async {
        page = 0
        hasNext = true
        // 이미 글이 있으면(탭 전환 등) 스피너로 깜빡이지 않고 기존 목록을 유지한 채 교체한다.
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
