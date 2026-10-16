//
//  SearchView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

enum SearchScope: Hashable {
    case posts, notes, people
}

struct SearchView: View {
    @State private var scope: SearchScope = .posts
    @State private var noteResults = NotesViewModel(search: "")
    @State private var peopleResults = PeopleSearchModel()
    @State private var matchedPeople: [PersonMatch] = []
    @State private var matchedRemote: [RemoteAccount] = []
    @State private var query = ""
    @State private var phase: LoadState<[FeedItem]> = .idle
    @State private var searchTask: Task<Void, Never>?
    @State private var remoteLookup: RemoteLookup = .off
    @State private var remoteFallback = false
    @State private var remoteTask: Task<Void, Never>?
    @Namespace private var zoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// 최근 검색 칩의 지우기(×) 아이콘 — 칩 라벨(.meta)과 함께 커지도록 고정 pt 를 우회한다.
    @ScaledMetric(relativeTo: .caption) private var recentClearSize: CGFloat = 9

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
    @State private var trendingNoteTags: [TrendingNoteTag] = []
    @State private var trendingNoteLinks: [TrendingNoteLink] = []
    @State private var suggestedAuthors: [SuggestedAuthor] = []
    /// 로그인한 사람의 팔로우 추천(마스토돈) — 있으면 익명 "작가" 레일 대신 선다.
    @State private var followSuggestions: [FollowSuggestion] = []
    @State private var remoteSuggestions: [RemoteAccount] = []

    var body: some View {
        // path 바인딩 금지 — tabBarMinimizeBehavior 가 죽는다(FeedView 참조).
        NavigationStack {
            Group {
                if scope == .people, !activeQuery.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    PeopleResultsList(model: peopleResults, query: query, retry: { runSearch(query) })
                } else if scope == .notes, !activeQuery.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    notesResults
                } else if resolvesRemotely(query) {
                    Color.clear
                } else {
                switch phase {
                case .idle:
                    idleState
                case .loading:
                    FeedSkeleton()
                        .background(Palette.readingBg)
                case .loaded(let items):
                    results(items)
                case .failed(let message):
                    ErrorState(message: message, retry: { runSearch(query) })
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // RootView 의 탭바 예약 safeAreaPadding 은 NavigationStack 안으로 넘어오지 않는다.
            .safeAreaPadding(.bottom, Metrics.tabBarReservedHeight)
            .safeAreaInset(edge: .top, spacing: 0) {
                if remoteLookup.isVisible {
                    VStack(spacing: 0) {
                        RemoteResolveSlot(lookup: $remoteLookup, onSignedIn: { scheduleRemoteLookup(query) })
                        Hairline()
                    }
                    .background(Palette.pageBg)
                    .transition(.opacity)
                }
            }
            .background(Palette.pageBg)
            // 스크롤을 내리면 탭바가 사라지고 올리면 돌아온다(스레드식) — 활성 스크롤 표면을 관측.
            .tracksTabBarVisibility()
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                // 푸시된 상세는 탭바 숨김을 추적하지 않는다(탭 루트 전용).
                if case .post(let username, let slug) = route, !reduceMotion {
                    RouteView(route: route)
                        .navigationTransition(.zoom(sourceID: "search-\(username)-\(slug)", in: zoomNS))
                } else {
                    RouteView(route: route)
                }
            }
            // 스택 안쪽에 부착 — 바깥이면 push 된 글 상세에도 검색바가 남는다.
            // 상단 고정(navigationBarDrawer) — iOS 26+ 는 .searchable 을 하단에 도킹하는데, 우리
            // 커스텀 FloatingTabBar 가 그 자리를 덮어 필드가 통째로 가려졌다. 검색 탭의 필드는
            // 제목 아래 상단에 항상 보이게 못 박는다.
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "글·노트 찾기")
            .searchScopes($scope, activation: .onTextEntry) {
                Text("글").tag(SearchScope.posts)
                Text("노트").tag(SearchScope.notes)
                Text("사람").tag(SearchScope.people)
            }
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
        .onChange(of: query) { _, newValue in
            remoteFallback = false
            scheduleSearch(newValue)
            scheduleRemoteLookup(newValue)
        }
        .onChange(of: scope) { runSearch(query) }
        .onChange(of: recents) { SearchRecents.save(recents) }
        .onSubmit(of: .search) { runSearch(query) }
        // 검색 결과 도착·최근 삭제는 손끝으로도 알린다 — 토글 버튼들과 같은 가벼운 임팩트.
        .sensoryFeedback(.impact(weight: .light), trigger: activeQuery)
        .sensoryFeedback(.impact(weight: .light), trigger: recents)
        // 알럿(중앙 모달) — confirmationDialog 은 regular width·세로 모두 부리 팝오버로 새어 나갔다.
        .alert("최근 검색을 모두 지울까요?", isPresented: $confirmingClear) {
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
                                                .typeScale(.meta)
                                                .foregroundStyle(Palette.chipText)
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            recents.removeAll { $0 == term }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: recentClearSize, weight: .semibold))
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

                trendingRail

                if AuthStore.shared.isSignedIn, !followSuggestions.isEmpty || !remoteSuggestions.isEmpty {
                    followSuggestionsRail
                }

                trendingNoteTagsRail

                trendingNoteLinksRail

                popularTagsRail

                if !AuthStore.shared.isSignedIn || followSuggestions.isEmpty {
                    suggestedAuthorsRail
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
        .brandRefreshable { await loadDiscovery() }
    }

    /// 지금 뜨는 글 레일 — idle 과 무결과(막다른 길 금지) 양쪽에서 같은 출발점으로 쓴다.
    @ViewBuilder private var trendingRail: some View {
        if !trending.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RailHeading("지금 뜨는 글")
                ForEach(Array(trending.prefix(5).enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        RowLayout(title: item.title.cleanedPreview, read: PostReadStore.shared.isRead(item.id)) {
                            if let tag = item.renderableTags.first {
                                Text("#\(ContentValidity.tagDisplay(tag))")
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                            }
                        } byline: {
                            AuthorByline(author: item.author, date: item.publishedAt, linked: true)
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    .cardQuickActions(item)
                    // 결과 행과 같은 글 푸시 — zoom 문법도 같아야 한다
                    // (idle/loaded 상호배타라 id 중복 안전).
                    .modifier(ZoomSource(
                        active: true,
                        id: "search-\(item.author.username)-\(item.slug)",
                        ns: zoomNS))
                    .rowDivider(index > 0)
                    .accessibilityIdentifier("search.trending.\(item.id)")
                }
            }
        }
    }

    /// 노트에서 뜨는 해시태그 — 마스토돈 둘러보기의 해시태그처럼 쓴 사람 수와 7일 막대.
    @ViewBuilder private var trendingNoteTagsRail: some View {
        if !trendingNoteTags.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                RailHeading("뜨는 해시태그")
                ForEach(trendingNoteTags) { trend in
                    NavigationLink(value: Route.noteTag(trend.tag)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "#\(trend.tag)")
                                    .typeScale(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text("\(trend.accounts)명이 이번 주에 썼어요")
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer(minLength: 8)
                            TrendSparkBars(history: trend.history)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("search.trendingTag.\(trend.tag)")
                }
            }
        }
    }

    @ViewBuilder private var trendingNoteLinksRail: some View {
        if !trendingNoteLinks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                RailHeading("뜨는 링크")
                ForEach(trendingNoteLinks) { trend in
                    NavigationLink(value: Route.noteLink(url: trend.url, title: trend.title)) {
                        HStack(spacing: 12) {
                            linkThumbnail(trend)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: trend.title?.isEmpty == false ? trend.title! : trend.host)
                                    .typeScale(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Group {
                                    if trend.title?.isEmpty == false {
                                        Text("\(trend.host) · \(trend.accounts)명이 이번 주에 공유했어요")
                                    } else {
                                        Text("\(trend.accounts)명이 이번 주에 공유했어요")
                                    }
                                }
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            TrendSparkBars(history: trend.history)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("search.trendingLink.\(trend.host)")
                }
            }
        }
    }

    @ViewBuilder private func linkThumbnail(_ trend: TrendingNoteLink) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.radiusInner, style: .continuous)
        if let image = trend.imageUrl.flatMap(URL.init(string:)) {
            RemoteImage(url: image, maxPixel: 200) { phase in
                if case .success(let loaded) = phase {
                    loaded.resizable().scaledToFill()
                } else {
                    Palette.chipBg
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(shape)
        } else {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 52, height: 52)
                .background(Palette.chipBg, in: shape)
        }
    }

    @ViewBuilder private var popularTagsRail: some View {
        let renderable = popularTags.filter { ContentValidity.isRenderableTag($0.tag) }
        if !renderable.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                RailHeading("인기 태그")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 불완전 자모·한 글자 부스러기 태그는 인기 태그에서도 거른다.
                        ForEach(renderable) { tag in
                            NavigationLink(value: Route.tag(tag.tag)) {
                                MutedChip(text: "#\(ContentValidity.tagDisplay(tag.tag))", tappable: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var followSuggestionsRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("팔로우 추천")
                .padding(.bottom, 4)
            ForEach(Array(followSuggestions.prefix(3).enumerated()), id: \.element.id) { index, suggestion in
                suggestionRow(suggestion)
                    .rowDivider(index > 0)
                    .transition(.opacity)
            }
            if !remoteSuggestions.isEmpty {
                otherServerLabel
                    .padding(.top, followSuggestions.isEmpty ? 2 : 14)
                    .rowDivider(!followSuggestions.isEmpty)
                ForEach($remoteSuggestions) { $account in
                    remoteSuggestionRow($account)
                        .rowDivider(account.id != remoteSuggestions.first?.id)
                }
            }
        }
        .accessibilityIdentifier("search.followSuggestions")
    }

    private var otherServerLabel: some View {
        Text("다른 서버")
            .typeScale(.meta)
            .foregroundStyle(Palette.secondary)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func remoteSuggestionRow(_ account: Binding<RemoteAccount>) -> some View {
        let value = account.wrappedValue
        return HStack(spacing: 11) {
            NavigationLink(value: Route.remoteAccount(id: value.id)) {
                HStack(spacing: 11) {
                    AvatarView(author: value.asAuthor, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: value.shownName)
                            .typeScale(.titleSmall)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(verbatim: "@\(value.acct)")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RemoteFollowButton(account: account, outlined: true)
            Color.clear
                .frame(width: 30, height: 1)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suggestion.remote.\(value.acct)")
    }

    private func suggestionRow(_ suggestion: FollowSuggestion) -> some View {
        HStack(spacing: 11) {
            NavigationLink(value: Route.author(username: suggestion.username)) {
                HStack(spacing: 11) {
                    AvatarView(author: suggestion.asAuthor, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(verbatim: suggestion.shownName)
                                .typeScale(.titleSmall)
                                .foregroundStyle(Palette.ink)
                            if suggestion.shownName != suggestion.username {
                                Text(verbatim: "@\(suggestion.username)")
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                        .lineLimit(1)
                        Group {
                            if suggestion.reason == .friends {
                                Text("내가 팔로우하는 \(suggestion.mutuals)명이 팔로우")
                            } else {
                                Text("요즘 많이 팔로우해요")
                            }
                        }
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            FollowButton(username: suggestion.username, initialStatus: suggestion.followSeed, outlined: true)
            Menu {
                Button("\(suggestion.shownName) 추천 안 보기") { dismissSuggestion(suggestion) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 30, height: 44)
                    .expandTapTarget(7)
            }
            .accessibilityLabel("더 보기")
            .accessibilityIdentifier("suggestion.more.\(suggestion.username)")
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suggestion.\(suggestion.username)")
    }

    private func dismissSuggestion(_ suggestion: FollowSuggestion) {
        let index = followSuggestions.firstIndex(of: suggestion)
        withAnimation(.snappy(duration: 0.25)) { followSuggestions.removeAll { $0 == suggestion } }
        Task {
            do {
                try await FollowSuggestionsAPI.dismiss(suggestion.username)
            } catch {
                if let index {
                    withAnimation(.snappy(duration: 0.25)) {
                        followSuggestions.insert(suggestion, at: min(index, followSuggestions.count))
                    }
                }
                ToastCenter.shared.show(String(localized: "추천을 지우지 못했어요"))
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
                            AvatarView(author: suggestion.author, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(suggestion.author.username)")
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
            // 피드와 같은 가드 — 자모·구두점만 있는 제목("ㅇㅇ")은 카드로 그리지 않는다.
            trending = Array(
                ((try? await BlogAPI.feed(sort: .trending, size: 6))?.items ?? [])
                    .filter(\.isRenderableCard).prefix(6))
        }
        if popularTags.isEmpty {
            popularTags = Array(((try? await BlogAPI.popularTags(limit: 12)) ?? []).prefix(12))
        }
        if suggestedAuthors.isEmpty {
            suggestedAuthors = (try? await BlogAPI.suggestedAuthors(limit: 5)) ?? []
        }
        if trendingNoteTags.isEmpty {
            trendingNoteTags = Array(((try? await NoteAPI.trendingTags()) ?? []).prefix(5))
        }
        if trendingNoteLinks.isEmpty {
            trendingNoteLinks = Array(((try? await NoteAPI.trendingLinks()) ?? []).prefix(5))
        }
        if AuthStore.shared.isSignedIn, followSuggestions.isEmpty {
            followSuggestions = (try? await FollowSuggestionsAPI.suggestions()) ?? []
        }
        if AuthStore.shared.isSignedIn, remoteSuggestions.isEmpty {
            remoteSuggestions = await FederationAPI.suggestions() ?? []
        }
    }

    /// 검색어와 겹치는 인기 태그 — 결과를 "태그 / 작가 / 글" 갈래로 보여주기 위한 얕은 매칭
    /// (이미 받아 둔 인기 세트 안에서만 — 전수 검색은 백엔드 몫).
    private var matchedTags: [TagCount] {
        guard !activeQuery.isEmpty else { return [] }
        return popularTags.filter { $0.tag.localizedCaseInsensitiveContains(activeQuery) }
    }

    /// 결과의 태그 칩 — 검색어와 겹치는 *실제* 인기 태그만. 입력어를 무조건 첫 칩으로 끼워 넣던
    /// 것을 뺀다: 아무 태그도 안 겹치는 검색어면 그 에코 칩이 tags 를 비우지 않아 무결과 폴백이
    /// 영영 안 뜨고, 존재하지 않는 태그 피드(빈 페이지 = 막다른 길)로 데려갔다. 입력어가 실제
    /// 태그와 정확히 겹치면 그 태그가 매치에 이미 들어 있어 여전히 첫 칩으로 선다.
    private var tagOptions: [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for t in matchedTags.map(\.tag).filter(ContentValidity.isRenderableTag)
        where seen.insert(t.lowercased()).inserted {
            tags.append(t)
        }
        return tags
    }

    @ViewBuilder
    private func results(_ rawItems: [FeedItem]) -> some View {
        // 피드와 같은 가드 — 자모·구두점만 있는 제목("ㅇㅇ")은 결과 카드로 그리지 않는다.
        let items = rawItems.filter(\.isRenderableCard)
        let tags = tagOptions
        let people = matchedPeople
        let remote = matchedRemote
        if items.isEmpty, tags.isEmpty, people.isEmpty, remote.isEmpty {
            noResults
        } else {
            // 결과는 태그 → 사람 → 글 갈래로. 다른 갈래가 있을 때만 "글" 라벨을 붙인다.
            let labelled = !tags.isEmpty || !people.isEmpty || !remote.isEmpty
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            RailHeading("관련 태그")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        NavigationLink(value: Route.tag(tag)) {
                                            MutedChip(text: "#\(ContentValidity.tagDisplay(tag))", tappable: true)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if !people.isEmpty || !remote.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            RailHeading("사람")
                            ForEach(people) { person in
                                NavigationLink(value: Route.author(username: person.username)) {
                                    HStack(spacing: 11) {
                                        AvatarView(author: person.asAuthor, size: 44)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: person.shownName)
                                                .typeScale(.titleSmall)
                                                .foregroundStyle(Palette.ink)
                                                .lineLimit(1)
                                            if person.shownName != person.username {
                                                Text(verbatim: "@\(person.username)")
                                                    .typeScale(.meta)
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
                                .accessibilityIdentifier("search.person.\(person.username)")
                            }
                            if !remote.isEmpty {
                                otherServerLabel
                                    .padding(.top, people.isEmpty ? 0 : 6)
                                ForEach(remote) { account in
                                    remotePersonLink(account)
                                }
                            }
                        }
                    }
                    if !items.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if labelled {
                                RailHeading("글").padding(.top, 4)
                            }
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                                    FeedRow(item: item, linked: true)
                                }
                                .buttonStyle(RowButtonStyle())
                                .cardQuickActions(item)
                                .accessibilityIdentifier("search.row.\(item.id)")
                                .modifier(ZoomSource(
                                    active: true,
                                    id: "search-\(item.author.username)-\(item.slug)",
                                    ns: zoomNS))
                                .rowDivider(index > 0)
                                .modifier(QuietAppear(index: index))
                                .task {
                                    if index >= items.count - 5 { await loadMore() }
                                }
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
            .background(Palette.readingBg)
        }
    }

    private func remotePersonLink(_ account: RemoteAccount) -> some View {
        NavigationLink(value: Route.remoteAccount(id: account.id)) {
            HStack(spacing: 11) {
                AvatarView(author: account.asAuthor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: account.shownName)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(verbatim: "@\(account.acct)")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        .accessibilityIdentifier("search.remotePerson.\(account.acct)")
    }

    /// 무결과 = 막다른 길 금지(§1 폴리시). 스톡 search-empty 대신, 이미 받아 둔 발견 레일을
    /// 같은 출발점으로 다시 깐다 — "이건 없지만 이쪽은 어때"로. 레일까지 비었으면(미로드)
    /// 폴백으로만 스톡 빈 상태를 둔다.
    @ViewBuilder private var noResults: some View {
        if trending.isEmpty, popularTags.isEmpty, suggestedAuthors.isEmpty {
            // 발견 레일까지 못 받은 드문 경우 — 스톡 회색 말풍선 대신 대기화면과 같은 언어로
            // 피드 탭으로 이어준다(막다른 길 금지).
            FeedPlaceholder(
                title: "‘\(query)’ 결과가 없어요",
                actionTitle: "피드에서 읽을 글 찾기",
                action: { TabRouter.shared.switchTo(0, reduceMotion: reduceMotion) }
            )
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    FeedPlaceholder(title: "‘\(query)’ 결과가 없어요")
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
        guard !resolvesRemotely(trimmed) else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    private func resolvesRemotely(_ text: String) -> Bool {
        scope == .posts && !remoteFallback && FederationAPI.queryDomain(text) != nil
    }

    private func scheduleRemoteLookup(_ text: String) {
        remoteTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FederationAPI.queryDomain(trimmed) != nil else {
            withAnimation(.smooth(duration: 0.2)) { remoteLookup = .off }
            return
        }
        guard AuthStore.shared.isSignedIn else {
            withAnimation(.smooth(duration: 0.2)) { remoteLookup = .done(.signIn) }
            return
        }
        remoteTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) { remoteLookup = .looking }
            let result = await FederationAPI.resolve(trimmed)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) { remoteLookup = .done(result) }
            switch result {
            case .account, .note:
                recordRecent(trimmed)
            case .hidden:
                remoteFallback = true
                if scope == .posts { runSearch(trimmed) }
            default:
                break
            }
        }
    }

    private func runSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !resolvesRemotely(trimmed) else { return }
        searchTask?.cancel()
        searchTask = Task { await search(trimmed) }
    }

    private var notesResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch noteResults.phase {
                case .failed(let message):
                    ErrorState(message: message, retry: { runSearch(query) })
                        .padding(.top, 16)
                case .loaded where noteResults.items.isEmpty:
                    FeedPlaceholder(title: "‘\(query)’ 결과가 없어요")
                        .padding(.top, 16)
                case .loaded:
                    ForEach(Array(noteResults.items.enumerated()), id: \.element.id) { index, note in
                        NoteFeedItem(
                            note: note,
                            onChange: { noteResults.replaced($0) },
                            onDelete: { noteResults.removed($0) })
                            .task { await noteResults.loadMoreIfNeeded(current: note) }
                        if index < noteResults.items.count - 1 {
                            Hairline().padding(.horizontal, -Metrics.noteGutter)
                        }
                    }
                default:
                    KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .environment(\.noteFilterContext, .public)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.noteGutter)
        }
        .background(Palette.readingBg)
        .noteTextLinks()
        .accessibilityIdentifier("search.notes")
    }

    private func search(_ text: String) async {
        if scope == .people {
            activeQuery = text
            await peopleResults.show(text)
            if PeopleAPI.isSearchable(text) { recordRecent(text) }
            return
        }
        if scope == .notes {
            activeQuery = text
            await noteResults.show(.search(text))
            recordRecent(text)
            return
        }
        generation += 1
        let myGen = generation
        // 결과를 보다가 검색어를 다듬는 경우엔 이전 결과를 그대로 둔다 — 스켈레톤으로
        // 갈아치우면 ScrollView identity 가 깨져 매번 깜빡이고 보던 위치가 사라진다.
        // 스켈레톤은 보여줄 결과가 아예 없는 첫 검색에만.
        if case .loaded = phase {} else { phase = .loading }
        do {
            async let people = try? PeopleAPI.search(text, size: 3)
            async let remote: [RemoteAccount]? = FederationAPI.queryDomain(text) == nil
                ? await FederationAPI.searchAccounts(text, limit: FederationAPI.suggestionLimit)
                : nil
            let result = try await BlogAPI.feed(query: text, page: 0, size: 30)
            let found = await people
            let foundRemote = await remote
            guard !Task.isCancelled, myGen == generation else { return }
            activeQuery = text
            page = 0
            hasNext = result.hasNext
            matchedPeople = found?.items ?? []
            matchedRemote = foundRemote ?? []
            phase = .loaded(result.items)
            // 결과가 실제로 온 뒤에 최근 검색에 남긴다 — 취소·실패한 검색어는 기록하지 않는다.
            recordRecent(text)
        } catch {
            // 재검색·클리어의 cancel() 은 URLError(.cancelled)→APIError.transport 로 올라온다 —
            // 취소를 '네트워크 오류'로 둔갑시키거나 클리어가 세운 .idle 을 덮지 않게 여기서 버린다.
            guard !Task.isCancelled, myGen == generation else { return }
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

/// 7일 동안 날마다 쓰인 수 — 마스토돈 트렌드 옆의 작은 막대. 가장 많은 날이 꽉 찬다.
private struct TrendSparkBars: View {
    let history: [Int]

    var body: some View {
        let peak = max(history.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, count in
                Capsule()
                    .fill(count == 0 ? Palette.hairlineStrong : Palette.secondary)
                    .frame(width: 4, height: max(3, 22 * CGFloat(count) / CGFloat(peak)))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
