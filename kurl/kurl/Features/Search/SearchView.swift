//
//  SearchView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var phase: LoadState<[FeedItem]> = .idle
    @State private var searchTask: Task<Void, Never>?
    @Namespace private var zoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 페이지네이션 — 결과 30개에서 끊기지 않게. generation 은 새 검색이 시작되면
    // 비행 중인 다음-페이지 응답을 버리는 스테일 가드.
    @State private var activeQuery = ""
    @State private var page = 0
    @State private var hasNext = false
    @State private var loadingMore = false
    @State private var generation = 0

    // 대기 화면의 출발점들 — 최근 검색은 기기 로컬, 트렌딩·태그·작가는 공개 API 1회 캐시.
    @State private var recents: [String] = SearchRecents.load()
    @State private var trending: [FeedItem] = []
    @State private var popularTags: [TagCount] = []
    @State private var suggestedAuthors: [SuggestedAuthor] = []

    var body: some View {
        // path 바인딩 금지 — tabBarMinimizeBehavior 가 죽는다(FeedView 참조).
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    idleState
                case .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 280)
                case .loaded(let items):
                    results(items)
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                           description: Text(message))
                }
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                if case .post(let username, let slug) = route, !reduceMotion {
                    RouteView(route: route)
                        .navigationTransition(.zoom(sourceID: "search-\(username)-\(slug)", in: zoomNS))
                } else {
                    RouteView(route: route)
                }
            }
            // 스택 안쪽에 부착 — 바깥이면 push 된 글 상세에도 검색바가 남는다.
            .searchable(text: $query, prompt: "글 검색")
        }
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onChange(of: recents) { SearchRecents.save(recents) }
        .onSubmit(of: .search) { runSearch(query) }
    }

    /// 대기 상태 — 장식이 아니라 출발점. 막연한 탐색 의도("뭐 볼 거 없나")가 그대로
    /// 행동이 되도록 최근 검색·인기 태그·추천 작가를 깐다. 전부 탭 = 즉시 이동.
    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !trending.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        RailHeading("지금 뜨는 글")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(trending) { item in
                                    NavigationLink(
                                        value: Route.post(
                                            username: item.author.username, slug: item.slug)
                                    ) {
                                        VStack(alignment: .leading, spacing: 7) {
                                            if let tag = item.tags.first {
                                                Text("#\(tag)")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(Palette.secondary)
                                            }
                                            Text(item.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .tracking(-0.2)
                                                .foregroundStyle(Palette.ink)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                            HStack(spacing: 5) {
                                                Text(item.author.username)
                                                    .lineLimit(1)
                                                if item.likeCount > 0 {
                                                    Text("·").foregroundStyle(Palette.faint)
                                                    HStack(spacing: 2) {
                                                        Image(systemName: "heart")
                                                            .font(.system(size: 9))
                                                        Text("\(item.likeCount)")
                                                    }
                                                }
                                            }
                                            .font(.system(size: 11))
                                            .foregroundStyle(Palette.secondary)
                                        }
                                        .padding(14)
                                        .frame(width: 200, height: 112, alignment: .topLeading)
                                        .background(
                                            Palette.cardBg,
                                            in: RoundedRectangle(
                                                cornerRadius: Metrics.radiusMini, style: .continuous))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(CardButtonStyle())
                                    .cardQuickActions(item)
                                    // 결과 카드와 같은 글 푸시 — zoom 문법도 같아야 한다
                                    // (idle/loaded 상호배타라 id 중복 안전).
                                    .modifier(ZoomSource(
                                        active: true,
                                        id: "search-\(item.author.username)-\(item.slug)",
                                        ns: zoomNS))
                                    .modifier(CardScrollFade(axis: .horizontal))
                                }
                            }
                        }
                    }
                }

                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            RailHeading("최근 검색")
                            Spacer()
                            Button("지우기") { recents = [] }
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recents, id: \.self) { term in
                                    HStack(spacing: 6) {
                                        Button {
                                            query = term
                                            runSearch(term)
                                        } label: {
                                            Text(term)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(Palette.chipText)
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            recents.removeAll { $0 == term }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(Palette.faint)
                                                .expandTapTarget(8)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(term) 삭제")
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(Palette.chipBg, in: Capsule())
                                }
                            }
                        }
                    }
                }

                if !popularTags.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        RailHeading("인기 태그")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(popularTags) { tag in
                                    NavigationLink(value: Route.tag(tag.tag)) {
                                        MutedChip(text: "#\(tag.tag)")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if !suggestedAuthors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        RailHeading("작가")
                            .padding(.bottom, 4)
                        ForEach(suggestedAuthors) { suggestion in
                            NavigationLink(
                                value: Route.author(username: suggestion.author.username)
                            ) {
                                HStack(spacing: 11) {
                                    AvatarView(author: suggestion.author, size: 42)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.author.username)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Palette.ink)
                                        if let bio = suggestion.author.bio, !bio.isEmpty {
                                            Text(bio)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Palette.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text("글 \(suggestion.postCount)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Palette.faint)
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                }

                if popularTags.isEmpty, suggestedAuthors.isEmpty, recents.isEmpty {
                    Text("제목과 내용으로 글을 검색합니다.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 80)
                }
            }
            .padding(.top, 18)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task { await loadDiscovery() }
    }

    private func loadDiscovery() async {
        if trending.isEmpty {
            trending = Array(
                ((try? await BlogAPI.feed(sort: .trending, size: 6))?.items ?? []).prefix(6))
        }
        if popularTags.isEmpty {
            popularTags = Array(((try? await BlogAPI.popularTags(limit: 12)) ?? []).prefix(12))
        }
        if suggestedAuthors.isEmpty {
            suggestedAuthors = (try? await BlogAPI.suggestedAuthors(limit: 5)) ?? []
        }
    }

    @ViewBuilder
    private func results(_ items: [FeedItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            // 검색도 browse 면 — 피드와 같은 카드 문법(웹 §10.1 예외와 동일 경계).
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                            BlogCard(item: item)
                        }
                        .buttonStyle(CardButtonStyle())
                        .cardQuickActions(item)
                        .modifier(ZoomSource(
                            active: true,
                            id: "search-\(item.author.username)-\(item.slug)",
                            ns: zoomNS))
                        .modifier(QuietAppear(index: index))
                        .modifier(CardScrollFade())
                        .task {
                            if index >= items.count - 5 { await loadMore() }
                        }
                    }
                    if loadingMore {
                        ProgressView().tint(Palette.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: Metrics.readingColumn)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { phase = .idle; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    private func runSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { await search(trimmed) }
    }

    private func search(_ text: String) async {
        generation += 1
        let myGen = generation
        phase = .loading
        recordRecent(text)
        do {
            let result = try await BlogAPI.feed(query: text, page: 0, size: 30)
            guard !Task.isCancelled, myGen == generation else { return }
            activeQuery = text
            page = 0
            hasNext = result.hasNext
            phase = .loaded(result.items)
        } catch {
            guard myGen == generation else { return }
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func recordRecent(_ term: String) {
        var next = recents.filter { $0 != term }
        next.insert(term, at: 0)
        recents = Array(next.prefix(8))
    }

    private func loadMore() async {
        guard hasNext, !loadingMore, case .loaded(let current) = phase else { return }
        loadingMore = true
        defer { loadingMore = false }
        let myGen = generation
        if let result = try? await BlogAPI.feed(query: activeQuery, page: page + 1, size: 30) {
            // 그 사이 새 검색이 시작됐으면 이 페이지는 옛 질의의 것 — 버린다.
            guard myGen == generation else { return }
            page += 1
            hasNext = result.hasNext
            phase = .loaded(current + result.items)
        }
    }
}

/// 최근 검색 — 기기 로컬에만 남는다(서버 전송 없음). 최대 8개.
enum SearchRecents {
    private static let key = "recentSearches"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ terms: [String]) {
        UserDefaults.standard.set(terms, forKey: key)
    }
}
