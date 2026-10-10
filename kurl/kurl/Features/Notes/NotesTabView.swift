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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $choice.path) {
            SwipePager(tabs: NoteFeedKind.tabs, selection: $choice.kind) { kind, active, warm in
                NoteFeedPage(kind: kind, model: model(kind), active: active, warm: warm)
            }
            .safeAreaBar(edge: .top) {
                FeedHeaderBar(items: NoteFeedKind.tabs, selection: $choice.kind, label: \.label) {
                    Menu {
                        NoteFeedMenu()
                    } label: {
                        FeedHeaderGlyph(systemImage: "line.3.horizontal")
                    }
                    .menuOrder(.fixed)
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(Text("노트 피드 더 보기"))
                    .accessibilityIdentifier("notes.more")
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
        .sheet(isPresented: Bindable(ScheduledNotesStore.shared).showing) {
            NavigationStack { ScheduledNotesView() }
        }
    }

    private func model(_ kind: NoteFeedKind) -> NotesViewModel {
        models[kind] ?? NotesViewModel(feed: kind)
    }
}
