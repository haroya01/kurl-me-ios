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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    // 페이지네이션 — 결과 30개에서 끊기지 않게. generation 은 새 검색이 시작되면
    // 비행 중인 다음-페이지 응답을 버리는 스테일 가드.
    @State private var activeQuery = ""
    @State private var page = 0
    @State private var hasNext = false
    @State private var loadingMore = false
    @State private var generation = 0

    // 대기 화면의 출발점들 — 최근 검색은 기기 로컬, 트렌딩·태그·작가는 공개 API 1회 캐시.
    @State private var recents: [String] = SearchRecents.load()
    @State private var confirmingClear = false
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
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, minHeight: 280)
                case .loaded(let items):
                    results(items)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { runSearch(query) }
                            .foregroundStyle(Palette.accent)
                    }
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
            // 태그·작가 갈래는 결과에서도 쓰므로 phase 와 무관하게 한 번 받아 둔다.
            .task { await loadDiscovery() }
            // `--query <term>` — simctl 은 터치를 못 넣으니, 결과·갈래·페이지네이션·무결과까지
            // 손 안 대고 닿는 검증 진입로(DEBUG 전용).
            .task {
                // 텍스트만 세팅 — 검색은 onChange→scheduleSearch 가 소유한다(최근 칩과 같은 경로).
                if let term = Config.launchValue(after: "--query"), query.isEmpty {
                    query = term
                }
            }
        }
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onChange(of: recents) { SearchRecents.save(recents) }
        .onSubmit(of: .search) { runSearch(query) }
        // 검색 결과 도착·최근 삭제는 손끝으로도 알린다 — 토글 버튼들과 같은 가벼운 임팩트.
        .sensoryFeedback(.impact(weight: .light), trigger: activeQuery)
        .sensoryFeedback(.impact(weight: .light), trigger: recents)
        .confirmationDialog("최근 검색을 모두 지울까요?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("지우기", role: .destructive) { recents = [] }
            Button("취소", role: .cancel) {}
        }
        // 첫 `.task` 가 실패하면 레일이 영구 빈 화면으로 굳는다 — 포그라운드 복귀 때
        // 빈 갈래만 다시 받아 자가치유(loadDiscovery 가 멱등이라 안전).
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await loadDiscovery() } }
        }
    }

    /// 대기 상태 — 장식이 아니라 출발점. 막연한 탐색 의도("뭐 볼 거 없나")가 그대로
    /// 행동이 되도록 최근 검색·인기 태그·추천 작가를 깐다. 전부 탭 = 즉시 이동.
    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                trendingRail

                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            RailHeading("최근 검색")
                            Spacer()
                            Button("지우기") { confirmingClear = true }
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recents, id: \.self) { term in
                                    HStack(spacing: 6) {
                                        Button {
                                            // 텍스트만 세팅 — 검색은 onChange→scheduleSearch 가 소유한다(중복 실행 금지).
                                            query = term
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

                popularTagsRail

                suggestedAuthorsRail

                if popularTags.isEmpty, suggestedAuthors.isEmpty, recents.isEmpty {
                    Text("제목과 내용으로 글을 검색합니다.")
                        .typeScale(.footnote)
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
        // 빈 레일을 당겨서 다시 받는다 — 첫 로드 실패의 두 번째 탈출구(scenePhase 와 짝).
        .refreshable { await loadDiscovery() }
        // 검색 idle = 안개가 서는 세 곳 중 하나(§1 폴리시). 유리 검색바·탭바가 굴절할
        // 배경을 깐다(피드·계정과 같은 레시피).
        .background(alignment: .top) {
            BrandMist()
                .frame(height: 240)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    /// 지금 뜨는 글 레일 — idle 과 무결과(막다른 길 금지) 양쪽에서 같은 출발점으로 쓴다.
    @ViewBuilder private var trendingRail: some View {
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
                                            .typeScale(.footnote)
                                            .foregroundStyle(Palette.secondary)
                                    }
                                    Text(item.title)
                                        .typeScale(.titleSmall)
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
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                                }
                                .padding(14)
                                .frame(width: 200, height: 112, alignment: .topLeading)
                                .background(
                                    Palette.cardBg,
                                    in: RoundedRectangle(
                                        cornerRadius: Metrics.radiusMini, style: .continuous))
                                // 흰 카드가 slate-50 위에서 안 보였다 — 다른 카드처럼
                                // 그림자(라이트)·보더(다크)로 면을 들어 올린다.
                                .overlay {
                                    if colorScheme == .dark {
                                        RoundedRectangle(
                                            cornerRadius: Metrics.radiusMini, style: .continuous)
                                            .strokeBorder(Palette.cardBorder, lineWidth: 1)
                                    }
                                }
                                .cardShadow()
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
                    .padding(.vertical, 6) // 카드 그림자가 레일에서 안 잘리게.
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder private var popularTagsRail: some View {
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
    }

    @ViewBuilder private var suggestedAuthorsRail: some View {
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
                                    .typeScale(.titleSmall)
                                    .foregroundStyle(Palette.ink)
                                if let bio = suggestion.author.bio, !bio.isEmpty {
                                    Text(bio)
                                        .typeScale(.lede)
                                        .foregroundStyle(Palette.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("글 \(suggestion.postCount)")
                                .typeScale(.meta)
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

    /// 검색어와 겹치는 인기 태그 — 결과를 "태그 / 작가 / 글" 갈래로 보여주기 위한 얕은 매칭
    /// (이미 받아 둔 인기 세트 안에서만 — 전수 검색은 백엔드 몫).
    private var matchedTags: [TagCount] {
        guard !activeQuery.isEmpty else { return [] }
        return popularTags.filter { $0.tag.localizedCaseInsensitiveContains(activeQuery) }
    }

    /// 검색어와 겹치는 추천 작가(이름/소개).
    private var matchedAuthors: [SuggestedAuthor] {
        guard !activeQuery.isEmpty else { return [] }
        return suggestedAuthors.filter {
            $0.author.username.localizedCaseInsensitiveContains(activeQuery)
                || ($0.author.bio?.localizedCaseInsensitiveContains(activeQuery) ?? false)
        }
    }

    /// 결과의 태그 칩 — 입력어 자체를 첫 태그로(인기 태그에 없어도 바로 그 태그 피드로 가게),
    /// 이어서 겹치는 인기 태그. 중복(대소문자 무시) 제거.
    private var tagOptions: [String] {
        let q = activeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var tags: [String] = []
        for t in [q] + matchedTags.map(\.tag) where seen.insert(t.lowercased()).inserted {
            tags.append(t)
        }
        return tags
    }

    @ViewBuilder
    private func results(_ items: [FeedItem]) -> some View {
        let tags = tagOptions
        let authors = matchedAuthors
        if items.isEmpty, tags.isEmpty, authors.isEmpty {
            noResults
        } else {
            // 검색도 browse 면 — 피드와 같은 카드 문법(웹 §10.1 예외와 동일 경계).
            // 결과는 태그 → 작가 → 글 갈래로. 다른 갈래가 있을 때만 "글" 라벨을 붙인다.
            let labelled = !tags.isEmpty || !authors.isEmpty
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            RailHeading("태그")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        NavigationLink(value: Route.tag(tag)) {
                                            MutedChip(text: "#\(tag)")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if !authors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            RailHeading("작가")
                            ForEach(authors) { suggestion in
                                NavigationLink(
                                    value: Route.author(username: suggestion.author.username)
                                ) {
                                    HStack(spacing: 11) {
                                        AvatarView(author: suggestion.author, size: 42)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.author.username)
                                                .typeScale(.titleSmall)
                                                .foregroundStyle(Palette.ink)
                                            if let bio = suggestion.author.bio, !bio.isEmpty {
                                                Text(bio)
                                                    .typeScale(.lede)
                                                    .foregroundStyle(Palette.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
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
                    if !items.isEmpty {
                        if labelled {
                            RailHeading("글").padding(.top, tags.isEmpty && authors.isEmpty ? 0 : 4)
                        }
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
                    }
                    if loadingMore {
                        KurlLoadingMark()
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

    /// 무결과 = 막다른 길 금지(§1 폴리시). 스톡 search-empty 대신, 이미 받아 둔 발견 레일을
    /// 같은 출발점으로 다시 깐다 — "이건 없지만 이쪽은 어때"로. 레일까지 비었으면(미로드)
    /// 폴백으로만 스톡 빈 상태를 둔다.
    @ViewBuilder private var noResults: some View {
        if trending.isEmpty, popularTags.isEmpty, suggestedAuthors.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("‘\(query)’ 결과가 없어요")
                            .typeScale(.titleSmall)
                            .foregroundStyle(Palette.ink)
                        Text("이런 글은 어때요")
                            .typeScale(.footnote)
                            .foregroundStyle(Palette.secondary)
                    }
                    trendingRail
                    popularTagsRail
                    suggestedAuthorsRail
                }
                .padding(.top, 18)
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
            // 서버 페이지가 겹쳐 와도 같은 id 카드가 두 번 박히지 않게 — 기존 id 와 겹치는 건 버린다.
            let seen = Set(current.map(\.id))
            phase = .loaded(current + result.items.filter { !seen.contains($0.id) })
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
