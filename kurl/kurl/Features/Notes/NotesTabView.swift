//
//  NotesTabView.swift
//  kurl
//

import SwiftUI

struct NotesTabView: View {
    @State private var choice = NoteFeedChoice.shared
    @State private var models = Dictionary(
        uniqueKeysWithValues: NoteFeedKind.tabs.map { ($0, NotesViewModel(feed: $0)) })
    @State private var loadedSignedIn: Bool?
    @State private var router = TabRouter.shared
    @State private var lists = NoteListsStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $choice.path) {
            ZStack {
                SwipePager(
                    tabs: NoteFeedKind.tabs, selection: $choice.kind, loadOnSelect: [.following], suspended: choice.more != nil
                ) { kind, active, warm in
                    NoteFeedPage(kind: kind, model: model(kind), active: active && choice.more == nil, warm: warm)
                }
                if let more = choice.more {
                    NoteMoreFeedPage(feed: more)
                        .id(more)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: choice.more)
            .safeAreaBar(edge: .top) {
                FeedHeaderBar(
                    items: NoteFeedKind.tabs,
                    selection: Binding(get: { choice.kind }, set: { choice.select($0) }),
                    label: \.label, moreChoice: choice.more?.choice(lists: lists.lists),
                    moreLabel: "노트 피드 더 보기", moreIdentifier: "notes.more"
                ) {
                    NoteFeedMenu()
                }
            }
            .background(alignment: .top) { FeedHeaderMist() }
            .background(Palette.readingBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) {
                RouteView(route: $0)
            }
            .noteTextLinks()
            .task(id: AuthStore.shared.isSignedIn) {
                let signedIn = AuthStore.shared.isSignedIn
                if loadedSignedIn == signedIn { return }
                loadedSignedIn = signedIn
                async let unread: Void = UnreadStore.shared.refresh()
                await NoteFeedPreferences.shared.hydrateIfNeeded()
                await NoteListsStore.shared.reload()
                await NoteFilterStore.shared.reload()
                await unread
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await UnreadStore.shared.refresh() } }
            }
            .onChange(of: AuthStore.shared.isSignedIn) { _, signedIn in
                if !signedIn { choice.signedOut() }
            }
            .onChange(of: lists.lists) { _, now in choice.listsChanged(now) }
            .loginPrompt(
                isPresented: Binding(
                    get: { choice.pendingLogin != nil },
                    set: { if !$0 { choice.pendingLogin = nil } }),
                message: choice.pendingLogin?.kind.loginMessage ?? ""
            ) { [feed = choice.pendingLogin] in
                if let feed { choice.show(feed) }
            }
        }
        .onChange(of: router.reselections) {
            if router.reselectedTab == 1 { choice.path = NavigationPath() }
        }
        .onChange(of: choice.posted?.id) {
            if let note = choice.posted { model(choice.kind).inserted(note) }
        }
        .sheet(isPresented: Bindable(NoteListsStore.shared).managing) {
            NoteListsSheet()
        }
    }

    private func model(_ kind: NoteFeedKind) -> NotesViewModel {
        models[kind] ?? NotesViewModel(feed: kind)
    }
}
