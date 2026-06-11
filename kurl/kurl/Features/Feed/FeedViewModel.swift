//
//  FeedViewModel.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import Observation

/// 피드 탭 — 최신/인기는 공개, 팔로잉은 인증 피드.
enum FeedSource: String, CaseIterable, Identifiable {
    case recent
    case trending
    case following

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: String(localized: "최신")
        case .trending: String(localized: "인기")
        case .following: String(localized: "팔로잉")
        }
    }
}

@MainActor
@Observable
final class FeedViewModel {
    let source: FeedSource

    private(set) var items: [FeedItem] = []
    private(set) var phase: LoadState<[FeedItem]> = .idle
    private(set) var isLoadingMore = false

    private var page = 0
    private var hasNext = true
    private let pageSize = 20

    init(source: FeedSource) {
        self.source = source
    }

    private func fetch(page: Int) async throws -> PublicFeedView {
        switch source {
        case .recent: try await BlogAPI.feed(sort: .recent, page: page, size: pageSize)
        case .trending: try await BlogAPI.feed(sort: .trending, page: page, size: pageSize)
        case .following: try await LibraryAPI.followingFeed(page: page, size: pageSize)
        }
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
            let view = try await fetch(page: 0)
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
            let view = try await fetch(page: page)
            items.append(contentsOf: view.items)
            hasNext = view.hasNext
            phase = .loaded(items)
        } catch {
            page -= 1
        }
    }
}
