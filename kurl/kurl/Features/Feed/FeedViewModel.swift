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
    /// 다음 페이지 실패 — 트리거인 아이템별 .task 가 1회성이라 조용히 끝난 피드처럼 보인다. footer 재시도의 신호.
    private(set) var loadMoreFailed = false
    /// 최신 피드에 끼워 넣을 발견 시리즈 한 장(웹 메인 피드의 시리즈 카드와 같은 자리). 그 외 정렬은 nil.
    private(set) var series: PublicSeriesCard?
    /// 최신 피드에 몇 칸마다 인터리브할 공개 연결 이벤트(웹 #828 미러) — 비로그인도 흐른다. 게이트 없는
    /// 공개 표면이라 실패는 조용히 빈 배열(피드를 막지 않게). 그 외 정렬은 빈 배열.
    private(set) var connectionEvents: [ConnectionEvent] = []

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
        series = nil
        connectionEvents = []
        page = 0
        hasNext = true
        loadMoreFailed = false
        phase = .idle
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty { phase = .loading }
        do {
            let view = try await fetch(page: 0)
            guard myEpoch == epoch else { return }
            // 페이지네이터 리셋은 성공 시에만 — fetch 전에 리셋하면 실패 후 loadMore 가 이미 있는 페이지를 다시 붙인다.
            page = 0
            hasNext = view.hasNext
            loadMoreFailed = false
            withAnimation(.easeInOut(duration: 0.2)) {
                // 제목이 사실상 빈("ㅇㅇ"·공백) 글은 카드로 그리지 않는다 — 풀 크롬으로 뜨면 피드가 부서져 보인다.
                items = view.items.filter(\.isRenderableCard)
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
            // 최신 피드엔 발견 시리즈 한 장을 끼워 넣는다(웹 메인 피드 패리티) — 본 피드를 막지 않게 곁에서.
            if source == .recent {
                Task { @MainActor [weak self] in
                    let fetched = try? await BlogAPI.discoverSeries(limit: 4)
                    guard let self, myEpoch == self.epoch else { return }
                    self.series = fetched?.first
                }
                // 공개 연결 흐름도 곁에서 — 비로그인 첫 피드에 몇 칸마다 인터리브(웹 #828 미러).
                // 게이트 없는 공개 표면이라 실패는 조용히 빈 배열(피드를 막지 않는다).
                Task { @MainActor [weak self] in
                    let fetched = (try? await CollectionsAPI.publicConnectionFeed(page: 0, size: 6)) ?? []
                    guard let self, myEpoch == self.epoch else { return }
                    self.connectionEvents = fetched
                }
            }
        } catch {
            if items.isEmpty {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            } else {
                // 무음이면 이전 데이터를 최신으로 오인한다 — 스피너만 닫히지 않게 한 줄.
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
        }
    }

    func loadMoreIfNeeded(current item: FeedItem) async {
        guard hasNext, !isLoadingMore else { return }
        // 마지막 카드에서만 발화하면 페이지 경계마다 스피너를 본다 — 태그 피드처럼 5개 선행.
        guard items.suffix(5).contains(where: { $0.id == item.id }) else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        let myEpoch = epoch
        page += 1
        do {
            let view = try await fetch(page: page)
            // reload 가 끼어들었으면 이 응답은 옛 세대 — 버린다(append 도 page 복원도 없음).
            guard myEpoch == epoch else { return }
            // 서버 페이지가 겹쳐 와도 같은 id 카드가 두 번 박히지 않게 — 기존 id 와 겹치는 건 버린다.
            // 빈 콘텐츠 카드도 함께 거른다(reload 와 같은 가드).
            let seen = Set(items.map(\.id))
            items.append(contentsOf: view.items.filter { !seen.contains($0.id) && $0.isRenderableCard })
            hasNext = view.hasNext
            phase = .loaded(items)
        } catch {
            guard myEpoch == epoch else { return }
            page = max(0, page - 1)
            loadMoreFailed = true
        }
    }

    /// footer '다시 시도' — 아이템별 .task 는 1회성이라 실패 뒤 같은 화면에선 재발화가 없다.
    func retryLoadMore() async {
        guard let last = items.last else { return }
        await loadMoreIfNeeded(current: last)
    }
}
