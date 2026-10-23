import SwiftUI

struct HomeView: View {
    @State private var choice = HomeFeedChoice.shared
    @State private var models = Dictionary(
        uniqueKeysWithValues: HomeFeedTab.allCases.map { ($0, HomeFeedViewModel(tab: $0)) })
    @State private var router = TabRouter.shared
    @Namespace private var zoomNS
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack(path: $choice.path) {
            SwipePager(
                tabs: HomeFeedTab.allCases, selection: $choice.tab, loadOnSelect: [.following], settled: settled
            ) { tab, active, warm in
                HomeFeedPage(model: model(tab), active: active, warm: warm)
                    .environment(\.postZoom, PostZoom(prefix: "post", ns: zoomNS, active: active))
            }
            .reservesTabBarSpace()
            .safeAreaBar(edge: .top) {
                FeedHeaderBar(
                    items: HomeFeedTab.allCases,
                    selection: Binding(get: { choice.tab }, set: { choice.select($0) }),
                    label: \.label, moreChoice: nil,
                    moreLabel: "홈 더 보기", moreIdentifier: "home.more",
                    showsMore: HomeMoreMenu.shows(tab: choice.tab)
                ) {
                    HomeMoreMenu()
                }
            }
            .background(Palette.readingBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                PostZoomDestination(
                    route: route, zoom: PostZoom(prefix: "post", ns: zoomNS),
                    fromRoot: !reduceMotion && choice.path.count == 1)
            }
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id)
            }
            .noteTextLinks()
            .task(id: AuthStore.shared.isSignedIn) {
                async let unread: Void = UnreadStore.shared.refresh()
                async let filters: Void = NoteFilterStore.shared.reload()
                await NoteFeedPreferences.shared.hydrateIfNeeded()
                await filters
                await unread
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await UnreadStore.shared.refresh() } }
            }
            .onChange(of: AuthStore.shared.isSignedIn) { _, signedIn in
                if !signedIn { choice.signedOut() }
            }
        }
        .environment(\.openNoteRoute) { choice.path.append($0) }
        .onChange(of: router.reselections) {
            if router.reselectedTab == TabRouter.homeTab { choice.path = NavigationPath() }
        }
        .onChange(of: choice.posted?.id) {
            if let note = choice.posted { model(choice.tab).inserted(note) }
        }
    }

    private var settled: Bool {
        switch model(choice.tab).phase {
        case .idle, .loading: false
        case .loaded, .failed: true
        }
    }

    private func model(_ tab: HomeFeedTab) -> HomeFeedViewModel {
        models[tab] ?? HomeFeedViewModel(tab: tab)
    }
}

struct HomeFeedPage: View {
    let model: HomeFeedViewModel
    var active = true
    var warm = true

    @State private var loadedSignedIn: Bool?
    @State private var position = ScrollPosition(edge: .top)
    @State private var router = TabRouter.shared
    @State private var choice = HomeFeedChoice.shared
    @State private var showLogin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ReadingColumn(
            spacing: 0, background: .clear, tracksTabBar: active, gutter: Metrics.noteGutter, position: $position
        ) {
            Color.clear.frame(height: 8)
            content.loadTransition(model.phase)
        }
        .onChange(of: router.topRequests) {
            guard active, router.topTab == TabRouter.homeTab else { return }
            withAnimation(reduceMotion ? nil : Motion.move) { position.scrollTo(edge: .top) }
        }
        .onChange(of: choice.arrivingID) { _, id in
            guard active, id != nil else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(reduceMotion ? nil : Motion.stage) { position.scrollTo(edge: .top) }
            }
        }
        .environment(\.noteFilterContext, .home)
        .environment(\.skeletonAnimates, active)
        .flushesRemoteSeen(while: measuresSeen)
        .onChange(of: showing) { _, now in
            if now {
                Task { await model.returned() }
            } else {
                model.left()
            }
        }
        .task(id: [warm, AuthStore.shared.isSignedIn]) {
            let signedIn = AuthStore.shared.isSignedIn
            guard warm, loadedSignedIn != signedIn else { return }
            loadedSignedIn = signedIn
            await model.reload(settlesLaunch: active)
        }
        .brandRefreshable { await model.refresh() }
        .onChange(of: NoteFeedPreferences.shared.changes) {
            if model.tab == .following { Task { await model.reload() } }
        }
        .onChange(of: NoteFeedPreferences.shared.mutes) { Task { await model.reload() } }
        .loginPrompt(isPresented: $showLogin, message: "팔로잉 피드를 보려면 로그인하세요")
    }

    @ViewBuilder
    private var content: some View {
        if model.tab == .following, !AuthStore.shared.isSignedIn {
            FeedPlaceholder(
                title: "로그인하면 팔로우한 사람의 노트와 글이 여기 모여요.",
                actionTitle: "로그인",
                action: { showLogin = true }
            )
            .padding(.top, 24)
        } else {
            switch model.phase {
            case .idle, .loading:
                NoteSkeleton()
            case .failed(let message):
                ErrorState(message: message, retry: { Task { await model.reload() } })
            case .loaded:
                if model.items.isEmpty {
                    empty.padding(.top, 24)
                } else {
                    rows
                    if model.next == nil, model.tab.hidesSeen, !model.isLoadingMore {
                        Hairline().padding(.horizontal, -Metrics.noteGutter)
                        allSeen.padding(.vertical, 24)
                    }
                }
            }
        }
    }

    private var allSeen: some View {
        FeedPlaceholder(
            title: "다 봤어요",
            actionTitle: "팔로잉 보기",
            actionIdentifier: "home.allSeen.following",
            action: { choice.select(.following) }
        )
    }

    private var showing: Bool {
        active && router.selection == TabRouter.homeTab && scenePhase == .active
    }

    private var measuresSeen: Bool {
        active && router.selection == TabRouter.homeTab && choice.path.isEmpty
    }

    @ViewBuilder
    private var empty: some View {
        switch model.tab {
        case .following:
            FeedPlaceholder(
                title: "팔로우한 사람의 노트와 글이 아직 없어요",
                actionTitle: "둘러보기",
                action: { TabRouter.shared.selection = TabRouter.exploreTab }
            )
        case .forYou:
            allSeen
        }
    }

    @ViewBuilder
    private var rows: some View {
        let items = model.items
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            Group {
                switch item.kind {
                case .note(let note):
                    NoteFeedItem(
                        note: note,
                        onChange: { model.replaced($0) },
                        onDelete: { model.removed($0) },
                        onQuoted: { model.inserted($0) },
                        repostedBy: note.repostedBy?.username
                    )
                    .modifier(QuietAppear(index: note.id == choice.arrivingID ? .max : index))
                    .modifier(NoteArrival(active: note.id == choice.arrivingID))
                case .post(let post):
                    PostFeedRow(post: post)
                        .modifier(QuietAppear(index: index))
                case .remote(.trending(let note)):
                    TrendingNoteRow(item: note, showsContext: false, context: Text("다른 서버"))
                        .modifier(QuietAppear(index: index))
                case .remote(.kept(let note)):
                    NoteFeedItem(
                        note: note,
                        onChange: { model.replaced($0) },
                        onDelete: { model.removed($0) },
                        context: Text("다른 서버"))
                        .modifier(QuietAppear(index: index))
                }
            }
            .environment(\.insideRoom, roomShownAbove(items, index))
            .marksRemoteSeen(dwellTarget(item))
            .marksHomeSeen(model.tab.hidesSeen && measuresSeen ? item.seenKey : nil)
            .task { await model.loadMoreIfNeeded(current: item) }
            if index < items.count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
        }
        if model.isLoadingMore {
            KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
        }
    }

    private func dwellTarget(_ item: HomeFeedItem) -> RemoteSeenTarget? {
        guard measuresSeen, model.tab.hidesSeen, case .remote(let remote) = item.kind,
              let uri = remote.seenURI else { return nil }
        return RemoteSeenTarget(uri: uri, feed: .forYou, noteID: remote.keptID, marks: false)
    }

    private func roomShownAbove(_ items: [HomeFeedItem], _ index: Int) -> Int64? {
        guard index > 0, let room = items[index].roomId, items[index - 1].roomId == room else { return nil }
        return room
    }
}
