//
//  NotesTabView.swift
//  kurl
//

import SwiftUI

struct NotesTabView: View {
    @State private var choice = NoteFeedChoice.shared
    @State private var models = Dictionary(
        uniqueKeysWithValues: NoteFeedKind.tabs.map { ($0, NotesViewModel(feed: $0)) })
    @State private var composingNote = false
    @State private var notesPosted = 0
    @State private var showLoginSheet = false
    @State private var loadedSignedIn: Bool?
    @State private var router = TabRouter.shared
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $choice.path) {
            SwipePager(tabs: NoteFeedKind.tabs, selection: $choice.kind) { kind, active, warm in
                NoteFeedPage(kind: kind, model: model(kind), active: active, warm: warm)
            }
            .safeAreaBar(edge: .top) {
                FeedHeaderBar(
                    items: NoteFeedKind.tabs, selection: $choice.kind, label: \.label,
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
        }
        .onChange(of: router.reselections) {
            if router.reselectedTab == 1 { choice.path = NavigationPath() }
        }
        .sheet(isPresented: Bindable(NoteListsStore.shared).managing) {
            NoteListsSheet()
        }
        .sheet(isPresented: Bindable(ScheduledNotesStore.shared).showing) {
            NavigationStack { ScheduledNotesView() }
        }
        .sheet(isPresented: $composingNote) {
            NoteComposeSheet(mode: .new(quote: nil, inReplyToId: nil)) { note in
                model(choice.kind).inserted(note)
                notesPosted += 1
            }
        }
        .loginPrompt(isPresented: $showLoginSheet, message: "로그인하고 노트 쓰기")
        .sensoryFeedback(.success, trigger: notesPosted)
        .overlay(alignment: .bottomTrailing) { composeButton }
    }

    private func model(_ kind: NoteFeedKind) -> NotesViewModel {
        models[kind] ?? NotesViewModel(feed: kind)
    }

    private func compose() {
        if AuthStore.shared.isSignedIn {
            composingNote = true
        } else {
            showLoginSheet = true
        }
    }

    private var composeButton: some View {
        let hidden = !choice.path.isEmpty || (tabBarVisibility?.hidden ?? false)
        return ZStack {
            if !hidden {
                GlassFAB(systemImage: "plus", label: "노트 쓰기", action: compose)
                    .accessibilityIdentifier("notes.fab")
                    .transition(.offset(y: 132).combined(with: .opacity))
            }
        }
        .padding(.trailing, Metrics.gutter)
        .padding(.bottom, 14)
    }
}
