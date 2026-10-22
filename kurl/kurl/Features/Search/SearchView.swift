import SwiftUI

enum SearchScope: Hashable {
    case posts, notes, people
}

enum ExploreLane: String, CaseIterable, Identifiable {
    case picks, remote, people

    var id: Self { self }

    var label: String {
        switch self {
        case .picks: String(localized: "추천")
        case .remote: String(localized: "다른 서버")
        case .people: String(localized: "사람")
        }
    }
}

// 목적지 클로저가 push 순간의 path 깊이를 읽는다 — @State 값으로 두면 마지막 body 때 값이 잡혀 늦다.
@MainActor
@Observable
private final class ExploreNavigation {
    var path = NavigationPath()
}

struct SearchView: View {
    @State private var scope: SearchScope = .posts
    @State private var noteResults = NotesViewModel(search: "")
    @State private var peopleResults = PeopleSearchModel()
    @State private var matchedPeople: [PersonMatch] = []
    @State private var matchedRemote: [RemoteAccount]?
    @State private var query = ""
    @State private var phase: LoadState<[FeedItem]> = .idle
    @State private var searchTask: Task<Void, Never>?
    @State private var remoteLookup: RemoteLookup = .off
    @State private var remoteFallback = false
    @State private var remoteTask: Task<Void, Never>?
    @State private var domainCompletion: DomainCompletion?
    @State private var shownDomains: [String] = []
    @State private var domainTask: Task<Void, Never>?
    @Namespace private var zoomNS
    @State private var navigation = ExploreNavigation()
    @State private var router = TabRouter.shared
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
    @State private var suggestedAuthors: [SuggestedAuthor] = []
    /// 로그인한 사람의 팔로우 추천(마스토돈) — 있으면 익명 "작가" 레일 대신 선다.
    @State private var followSuggestions: [FollowSuggestion] = []
    @State private var remoteSuggestions: [RemoteAccount] = []
    @State private var lane: ExploreLane = .picks
    @State private var streams = Dictionary(
        uniqueKeysWithValues: RemoteStreamFeed.allCases.map { ($0, RemoteStreamModel(feed: $0)) })

    var body: some View {
        NavigationStack(path: Bindable(navigation).path) {
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
            .reservesTabBarSpace()
            .safeAreaInset(edge: .top, spacing: 0) {
                if let draft = FederationAPI.handleDraft(query),
                   case let handles = DomainCompletion.rows(draft, domainCompletion, interim: shownDomains),
                   !handles.isEmpty {
                    VStack(spacing: 0) {
                        DomainCompletionSlot(draft: draft, handles: handles, pick: pickDomain)
                        Hairline()
                    }
                    .background(Palette.readingBg)
                    .transition(.opacity)
                } else if remoteLookup.isVisible {
                    VStack(spacing: 0) {
                        RemoteResolveSlot(lookup: $remoteLookup, onSignedIn: { scheduleRemoteLookup(query) })
                        Hairline()
                    }
                    .background(Palette.readingBg)
                    .transition(.opacity)
                }
            }
            .background(Palette.readingBg)
            // 스크롤을 내리면 탭바가 사라지고 올리면 돌아온다(스레드식) — 활성 스크롤 표면을 관측.
            .tracksTabBarVisibility()
            .navigationTitle("둘러보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    GlassSegmentSwitcher(items: ExploreLane.allCases, selection: $lane, label: \.label)
                        .opacity(query.isEmpty ? 1 : 0)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(for: Route.self) { route in
                PostZoomDestination(
                    route: route, zoom: PostZoom(prefix: "search", ns: zoomNS),
                    fromRoot: !reduceMotion && navigation.path.count == 1)
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
                #if DEBUG
                if let raw = Config.launchValue(after: "--explore-lane"), let picked = ExploreLane(rawValue: raw) {
                    lane = picked
                }
                #endif
            }
        }
        .onChange(of: query) { _, newValue in
            remoteFallback = false
            scheduleDomainCompletion(newValue)
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

    private var idleState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SearchingOnly {
                    recentsRail.padding(.bottom, 18)
                    tagStrip.padding(.bottom, 18)
                }
                switch lane {
                case .picks: picks
                case .remote: remoteLane
                case .people: peopleLane
                }
            }
            .padding(.top, lane == .people ? 14 : 0)
            .padding(.bottom, 16)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, lane == .people ? Metrics.gutter : Metrics.noteGutter)
        }
        .scrollIndicators(.hidden)
        // 숨은 검색 범위 막대도 위 가장자리 효과에 제 높이를 잡아, 그 띠가 첫 행의 터치를 먹는다.
        .scrollEdgeEffectHidden(true, for: .top)
        .noteTextLinks()
        .brandRefreshable {
            async let discovery: Void = loadDiscovery()
            await streams[lane == .remote ? .latest : .trending]?.reload()
            await discovery
        }
    }

    @ViewBuilder private var picks: some View {
        ForEach(Array(trending.enumerated()), id: \.element.id) { index, item in
            if index > 0 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
            PostFeedRow(post: item)
                .environment(\.postZoom, PostZoom(prefix: "search", ns: zoomNS))
                .accessibilityIdentifier("search.trending.\(item.id)")
            if index == min(2, trending.count - 1) {
                Hairline().padding(.horizontal, -Metrics.noteGutter)
                peopleStrip.padding(.vertical, 18)
            }
        }
        if trending.isEmpty { peopleStrip.padding(.vertical, 18) }
        Hairline().padding(.horizontal, -Metrics.noteGutter)
        if let model = streams[.trending] {
            RemoteStreamRows(model: model, gutter: Metrics.noteGutter)
                .task { await model.loadIfNeeded() }
        }
    }

    @ViewBuilder private var remoteLane: some View {
        if let model = streams[.latest] {
            let measuring = router.selection == TabRouter.exploreTab && navigation.path.isEmpty
            RemoteStreamRows(model: model, gutter: Metrics.noteGutter, measuresSeen: measuring)
                .task { await model.loadIfNeeded() }
                .flushesRemoteSeen(while: measuring)
        }
    }

    @ViewBuilder private var peopleLane: some View {
        if AuthStore.shared.isSignedIn, !followSuggestions.isEmpty || !remoteSuggestions.isEmpty {
            followSuggestionsRail
                .padding(.bottom, 26)
        }
        suggestedAuthorsRail
    }

    @ViewBuilder private var tagStrip: some View {
        let noteTags = trendingNoteTags.map(\.tag)
        let postTags = popularTags.filter { ContentValidity.isRenderableTag($0.tag) }
            .filter { tag in !noteTags.contains { $0.caseInsensitiveCompare(tag.tag) == .orderedSame } }
        if !noteTags.isEmpty || !postTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(noteTags, id: \.self) { tag in
                        NavigationLink(value: Route.noteTag(tag)) {
                            MutedChip(text: "#\(tag)", tappable: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.trendingTag.\(tag)")
                    }
                    ForEach(postTags) { tag in
                        NavigationLink(value: Route.tag(tag.tag)) {
                            MutedChip(text: "#\(ContentValidity.tagDisplay(tag.tag))", tappable: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder private var peopleStrip: some View {
        let people = followSuggestions.isEmpty
            ? suggestedAuthors.map { ($0.author, String(localized: "글 \($0.postCount)")) }
            : followSuggestions.map {
                ($0.asAuthor, $0.reason == .friends
                    ? String(localized: "내가 팔로우하는 \($0.mutuals)명이 팔로우")
                    : String(localized: "요즘 많이 팔로우해요"))
            }
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RailHeading("팔로우 추천")
                    Spacer()
                    Button {
                        lane = .people
                    } label: {
                        HStack(spacing: 3) {
                            Text("더 보기")
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .typeScale(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(people.prefix(8).enumerated()), id: \.offset) { _, person in
                            personCard(person.0, reason: person.1)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func personCard(_ author: Author, reason: String) -> some View {
        VStack(spacing: 8) {
            NavigationLink(value: Route.author(username: author.username)) {
                VStack(spacing: 6) {
                    AvatarView(author: author, size: 56)
                    Text(verbatim: author.displayName ?? author.username)
                        .typeScale(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(verbatim: reason)
                        .typeScale(.footnote)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(height: 30, alignment: .top)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            FollowButton(username: author.username, outlined: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(width: 140)
        .background(Palette.cardBg, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.personCard.\(author.username)")
    }

    @ViewBuilder private var recentsRail: some View {
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
            ForEach(Array(followSuggestions.enumerated()), id: \.element.id) { index, suggestion in
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
        let signedIn = AuthStore.shared.isSignedIn
        let needsPeople = followSuggestions.isEmpty
        let needsRemote = remoteSuggestions.isEmpty
        async let feed = Self.fetch(trending.isEmpty) { try await BlogAPI.feed(sort: .trending, size: 10) }
        async let tags = Self.fetch(popularTags.isEmpty) { try await BlogAPI.popularTags(limit: 12) }
        async let authors = Self.fetch(suggestedAuthors.isEmpty) { try await BlogAPI.suggestedAuthors(limit: 5) }
        async let noteTags = Self.fetch(trendingNoteTags.isEmpty) { try await NoteAPI.trendingTags() }
        async let people = Self.fetch(signedIn && needsPeople) {
            try await FollowSuggestionsAPI.suggestions()
        }
        async let remote = Self.fetch(signedIn && needsRemote) { await FederationAPI.suggestions() }
        let (feedPage, tagList, authorList, noteTagList, peopleList, remoteList) =
            await (feed, tags, authors, noteTags, people, remote)
        // 피드와 같은 가드 — 자모·구두점만 있는 제목("ㅇㅇ")은 카드로 그리지 않는다.
        if let feedPage { trending = Array(feedPage.items.filter(\.isRenderableCard).prefix(10)) }
        if let tagList { popularTags = Array(tagList.prefix(12)) }
        if let authorList { suggestedAuthors = authorList }
        if let noteTagList { trendingNoteTags = Array(noteTagList.prefix(5)) }
        if let peopleList { followSuggestions = peopleList }
        if let remoteList { remoteSuggestions = remoteList ?? [] }
    }

    private static func fetch<T>(_ needed: Bool, _ request: () async throws -> T) async -> T? {
        guard needed else { return nil }
        return try? await request()
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
        let remote = matchedRemote ?? []
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
                            } else if RemoteSearchHint.shows(
                                in: .postsPeopleRail, query: query, remote: matchedRemote, localPeople: people.count
                            ) {
                                RemoteSearchHintLine()
                                    .padding(.top, 6)
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
        guard scope == .posts, !remoteFallback else { return false }
        return FederationAPI.queryDomain(text) != nil || completionHolds(text)
    }

    private func completionHolds(_ text: String) -> Bool {
        DomainCompletion.holdsResolve(FederationAPI.handleDraft(text), domainCompletion)
    }

    private func scheduleDomainCompletion(_ text: String) {
        guard let draft = FederationAPI.handleDraft(text) else {
            domainTask?.cancel()
            domainCompletion = nil
            shownDomains = []
            return
        }
        if domainCompletion?.prefix == draft.domain { return }
        domainTask?.cancel()
        if case .loaded(_, let domains)? = domainCompletion { shownDomains = domains }
        domainCompletion = .loading(prefix: draft.domain)
        domainTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = await FederationAPI.domains(prefix: draft.domain)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) {
                domainCompletion = found.map { .loaded(prefix: draft.domain, domains: $0) }
                    ?? .unavailable(prefix: draft.domain)
            }
            scheduleSearch(query)
            scheduleRemoteLookup(query)
        }
    }

    private func pickDomain(_ handle: String) {
        guard let draft = FederationAPI.handleDraft(handle) else { return }
        domainTask?.cancel()
        domainCompletion = .loaded(prefix: draft.domain, domains: [draft.domain])
        query = handle
    }

    private func scheduleRemoteLookup(_ text: String) {
        remoteTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FederationAPI.queryDomain(trimmed) != nil, !completionHolds(trimmed) else {
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
            matchedRemote = foundRemote
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

private struct SearchingOnly<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.isSearching) private var isSearching

    var body: some View {
        if isSearching { content }
    }
}
