//
//  FeedViewModel.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import Observation

/// 피드 탭 — 최신/인기는 공개, 추천(For You)·구독함은 인증 피드.
enum FeedSource: String, CaseIterable, Identifiable {
    case recent
    case trending
    case forYou
    case following

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: String(localized: "최신")
        case .trending: String(localized: "인기")
        case .forYou: String(localized: "추천")
        case .following: String(localized: "구독함")
        }
    }

    /// 본인 신호로 만드는 면 — 로그아웃이면 게이트하고 인증 전환에 초기화한다.
    var requiresAuth: Bool { self == .forYou || self == .following }
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
    /// reload 가 in-flight loadMore 의 스테일 응답을 폐기하기 위한 세대 토큰.
    private var epoch = 0

    init(source: FeedSource) {
        self.source = source
    }

    private func fetch(page: Int) async throws -> PublicFeedView {
        switch source {
        case .recent: try await BlogAPI.feed(sort: .recent, page: page, size: pageSize)
        case .trending: try await BlogAPI.feed(sort: .trending, page: page, size: pageSize)
        case .forYou: try await LibraryAPI.forYouFeed(page: page, size: pageSize)
        case .following: try await LibraryAPI.followingFeed(page: page, size: pageSize)
        }
    }

    func loadInitial() async {
        guard case .idle = phase else { return }
        await reload()
    }

    /// 인증 전환(다른 계정 로그인/로그아웃) 시 — 이전 계정의 피드가 남지 않게 처음으로.
    func resetForAuthChange() {
        epoch += 1
        items = []
        page = 0
        hasNext = true
        phase = .idle
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        page = 0
        hasNext = true
        if items.isEmpty { phase = .loading }
        do {
            let view = try await fetch(page: 0)
            guard myEpoch == epoch else { return }
            hasNext = view.hasNext
            withAnimation(.easeInOut(duration: 0.2)) {
                items = view.items
                phase = .loaded(items)
            }
            // 구독함 머리쪽은 조용히 기기로 — 도착한 글은 지하철에서도 읽혀야 한다.
            if source == .following {
                let head = view.items.prefix(10).map { ($0.author.username, $0.slug) }
                Task(priority: .utility) {
                    for (username, slug) in head {
                        await OfflineStore.shared.download(username: username, slug: slug)
                    }
                }
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
        let myEpoch = epoch
        page += 1
        do {
            let view = try await fetch(page: page)
            // reload 가 끼어들었으면 이 응답은 옛 세대 — 버린다(append 도 page 복원도 없음).
            guard myEpoch == epoch else { return }
            items.append(contentsOf: view.items)
            hasNext = view.hasNext
            phase = .loaded(items)
        } catch {
            guard myEpoch == epoch else { return }
            page = max(0, page - 1)
        }
    }
}
