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

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0) {
                Color.clear.frame(height: 8)
                composePlaceholder
                content
            }
            .navigationTitle("노트")
            .navigationBarTitleDisplayMode(.inline)
            .tracksTabBarVisibility()
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
    }

    private func compose() {
        if AuthStore.shared.isSignedIn {
            composingNote = true
        } else {
            showLoginSheet = true
        }
    }

    private var composePlaceholder: some View {
        Button(action: compose) {
            HStack(spacing: 10) {
                Text("지금 떠오른 생각을 짧게 남겨 보세요")
                    .typeScale(.body)
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.link)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusControl)
                    .stroke(Palette.hairlineStrong, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusControl))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("노트 쓰기")
        .accessibilityIdentifier("notes.compose")
        .padding(.bottom, 6)
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
