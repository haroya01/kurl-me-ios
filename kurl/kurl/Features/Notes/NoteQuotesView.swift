//
//  NoteQuotesView.swift
//  kurl
//

import SwiftUI

struct NoteQuotesView: View {
    @State private var notes: NotesViewModel

    init(noteId: Int64) {
        _notes = State(initialValue: NotesViewModel(quotesOf: noteId))
    }

    var body: some View {
        ReadingColumn(spacing: 0, background: Palette.readingBg, gutter: Metrics.noteGutter) {
            switch notes.phase {
            case .idle, .loading:
                KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 320)
            case .failed(let message):
                ErrorState(message: message, retry: { Task { await notes.reload() } })
            case .loaded:
                if notes.items.isEmpty {
                    Text("아직 이 노트를 인용한 노트가 없어요")
                        .typeScale(.note)
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 56)
                } else {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
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
        .navigationTitle("인용한 노트")
        .noteTextLinks()
        .navigationBarTitleDisplayMode(.inline)
        .brandRefreshable { await notes.reload() }
        .task { if notes.items.isEmpty { await notes.reload() } }
    }
}
