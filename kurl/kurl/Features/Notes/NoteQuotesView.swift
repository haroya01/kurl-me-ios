//
//  NoteQuotesView.swift
//  kurl
//

import SwiftUI

struct NoteQuotesView: View {
    let noteId: Int64
    @State private var notes: NotesViewModel
    @State private var posts: [FeedItem] = []
    @State private var postsLoaded = false

    init(noteId: Int64) {
        self.noteId = noteId
        _notes = State(initialValue: NotesViewModel(quotesOf: noteId))
    }

    var body: some View {
        ReadingColumn(spacing: 0, background: Palette.readingBg, gutter: Metrics.noteGutter) {
            switch notes.phase {
            case .idle, .loading:
                NoteSkeleton()
            case .failed(let message):
                ErrorState(message: message, retry: { Task { await reload() } })
            case .loaded:
                if !posts.isEmpty {
                    carryingPosts
                }
                if notes.items.isEmpty && posts.isEmpty {
                    if postsLoaded {
                        Text("아직 이 노트를 인용한 노트나 글이 없어요")
                            .typeScale(.note)
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 56)
                    }
                } else {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteFeedItem(
                            note: note,
                            onChange: { notes.replaced($0) },
                            onDelete: { notes.removed($0) })
                            .task { await notes.loadMoreIfNeeded(current: note) }
                        if index < notes.items.count - 1 {
                            Hairline().padding(.horizontal, -Metrics.noteGutter)
                        }
                    }
                }
            }
        }
        .environment(\.noteFilterContext, notes.filterContext)
        .navigationTitle("인용")
        .noteTextLinks()
        .navigationBarTitleDisplayMode(.inline)
        .brandRefreshable { await reload() }
        .task { if notes.items.isEmpty { await reload() } }
    }

    /// 이 노트를 카드로 실은 블로그 글 — 노트 인용보다 위, 같은 화면의 다른 갈래.
    private var carryingPosts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("이 노트를 실은 글")
                .typeScale(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 14)
            ForEach(posts) { item in
                NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                    FeedRow(item: item)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quotingPost.\(item.id)")
                Hairline()
            }
        }
        .padding(.bottom, notes.items.isEmpty ? 0 : 6)
    }

    private func reload() async {
        async let quotingPosts = try? NoteAPI.quotingPosts(of: noteId)
        await notes.reload()
        posts = await quotingPosts?.items ?? []
        postsLoaded = true
    }
}
