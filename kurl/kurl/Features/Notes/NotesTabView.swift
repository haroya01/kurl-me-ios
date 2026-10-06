//
//  NotesTabView.swift
//  kurl
//

import SwiftUI

struct NotesTabView: View {
    @State private var notes = NotesViewModel()
    @State private var composingNote = false
    @State private var notesPosted = 0
    @State private var showLoginSheet = false
    @State private var loadedSignedIn: Bool?
    @Environment(\.tabBarVisibility) private var tabBarVisibility

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0, background: Palette.readingBg, tracksTabBar: true) {
                Color.clear.frame(height: 8)
                composePlaceholder
                content
            }
            .navigationTitle("노트")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) {
                RouteView(route: $0)
            }
            .task(id: AuthStore.shared.isSignedIn) {
                let signedIn = AuthStore.shared.isSignedIn
                if loadedSignedIn == signedIn { return }
                loadedSignedIn = signedIn
                await notes.reload()
            }
            .brandRefreshable {
                await notes.reload()
            }
            .sheet(isPresented: $composingNote) {
                NoteComposeSheet(mode: .new(quote: nil, inReplyToId: nil)) { note in
                    notes.inserted(note)
                    notesPosted += 1
                }
            }
            .loginPrompt(isPresented: $showLoginSheet, message: "로그인하고 노트 쓰기")
            .sensoryFeedback(.success, trigger: notesPosted)
        }
        .overlay(alignment: .bottomTrailing) { composeButton }
    }

    private func compose() {
        if AuthStore.shared.isSignedIn {
            composingNote = true
        } else {
            showLoginSheet = true
        }
    }

    private var composeButton: some View {
        let hidden = tabBarVisibility?.hidden ?? false
        return GlassFAB(systemImage: "plus", label: "노트 쓰기", action: compose)
            .accessibilityIdentifier("notes.fab")
            .padding(.trailing, Metrics.gutter)
            .padding(.bottom, 14)
            .offset(y: hidden ? 132 : 0)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }

    private var composePlaceholder: some View {
        let me = AuthStore.shared.me
        return Button(action: compose) {
            HStack(alignment: .center, spacing: 12) {
                if let me, AuthStore.shared.isSignedIn {
                    AvatarView(
                        author: Author(id: me.id ?? 0, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl),
                        size: 36)
                } else {
                    Circle().fill(Palette.hairline).frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let name = me?.username, AuthStore.shared.isSignedIn {
                        Text(name)
                            .typeScale(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                    }
                    Text(AuthStore.shared.isSignedIn ? "지금 떠오른 생각을 짧게 남겨 보세요" : "로그인하고 노트 쓰기")
                        .typeScale(.body)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("노트 쓰기")
        .accessibilityIdentifier("notes.compose")
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder
    private var content: some View {
        switch notes.phase {
        case .idle, .loading:
            KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 320)
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await notes.reload() } })
        case .loaded:
            if notes.items.isEmpty {
                FeedPlaceholder(
                    title: "아직 노트가 없어요",
                    message: "제목도 형식도 없이, 지금 떠오른 한 줄을 남기는 자리예요.",
                    actionTitle: "첫 노트 쓰기",
                    prominent: true,
                    action: compose
                )
                .padding(.top, 56)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
                            note: note,
                            onChange: { notes.replaced($0) },
                            onDelete: { notes.removed($0) }
                        )
                        .modifier(QuietAppear(index: index))
                        .task { await notes.loadMoreIfNeeded(current: note) }
                        if index < notes.items.count - 1 { Hairline() }
                    }
                    if notes.isLoadingMore {
                        KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
            }
        }
    }
}
