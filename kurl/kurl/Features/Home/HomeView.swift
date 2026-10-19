//
//  HomeView.swift
//  kurl
//

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
            ZStack {
                SwipePager(
                    tabs: HomeFeedTab.allCases, selection: $choice.tab, loadOnSelect: [.following],
                    suspended: choice.more != nil
                ) { tab, active, warm in
                    HomeFeedPage(model: model(tab), active: active && choice.more == nil, warm: warm)
                }
                if let more = choice.more {
                    FeedPage(source: more, active: true, warm: true, zoom: zoomNS)
                        .id(more)
                        .transition(.opacity)
                        .swipesBack { choice.leaveMore() }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: choice.more)
            .reservesTabBarSpace()
            .safeAreaBar(edge: .top) {
                FeedHeaderBar(
                    items: HomeFeedTab.allCases,
                    selection: Binding(get: { choice.tab }, set: { choice.select($0) }),
                    label: \.label, moreChoice: choice.more?.moreChoice,
                    moreLabel: "홈 더 보기", moreIdentifier: "home.more"
                ) {
                    HomeMoreMenu()
                }
            }
            .background(Palette.readingBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                if case .post(let username, let slug) = route, !reduceMotion {
                    RouteView(route: route)
                        .navigationTransition(.zoom(sourceID: "post-\(username)-\(slug)", in: zoomNS))
                } else {
                    RouteView(route: route)
                }
            }
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id)
            }
            .noteTextLinks()
            .task(id: AuthStore.shared.isSignedIn) {
                async let unread: Void = UnreadStore.shared.refresh()
                await NoteFeedPreferences.shared.hydrateIfNeeded()
                await NoteFilterStore.shared.reload()
                await unread
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await UnreadStore.shared.refresh() } }
            }
            .onChange(of: AuthStore.shared.isSignedIn) { _, signedIn in
                if !signedIn { choice.signedOut() }
            }
            .loginPrompt(
                isPresented: Binding(
                    get: { choice.pendingMoreLogin != nil },
                    set: { if !$0 { choice.pendingMoreLogin = nil } }),
                message: choice.pendingMoreLogin?.loginMessage ?? ""
            ) { [feed = choice.pendingMoreLogin] in
                if let feed { choice.show(feed) }
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

    var body: some View {
        ReadingColumn(
            spacing: 0, background: .clear, tracksTabBar: active, gutter: Metrics.noteGutter, position: $position
        ) {
            Color.clear.frame(height: 8)
            content
        }
        .onChange(of: router.topRequests) {
            guard active, router.topTab == TabRouter.homeTab else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { position.scrollTo(edge: .top) }
        }
        .onChange(of: choice.arrivingID) { _, id in
            guard active, id != nil else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { position.scrollTo(edge: .top) }
            }
        }
        .environment(\.noteFilterContext, .home)
        .task(id: [warm, AuthStore.shared.isSignedIn]) {
            let signedIn = AuthStore.shared.isSignedIn
            guard warm, loadedSignedIn != signedIn else { return }
            loadedSignedIn = signedIn
            await model.reload()
        }
        .brandRefreshable { await model.reload() }
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
                }
            }
        }
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
        case .latest, .trending:
            FeedPlaceholder(
                title: "아직 노트와 글이 없어요",
                actionTitle: "둘러보기",
                action: { TabRouter.shared.selection = TabRouter.exploreTab }
            )
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
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
                }
            }
            .task { await model.loadMoreIfNeeded(current: item) }
            if index < model.items.count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
        }
        if model.isLoadingMore {
            KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
        }
    }
}
