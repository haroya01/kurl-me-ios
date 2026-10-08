//
//  LinkNotesView.swift
//  kurl
//

import SwiftUI

struct LinkNotesView: View {
    let url: String
    let title: String?
    @State private var notes: NotesViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(url: String, title: String?) {
        self.url = url
        self.title = title
        _notes = State(initialValue: NotesViewModel(link: url))
    }

    var body: some View {
        ReadingColumn(spacing: 0, background: Palette.readingBg, gutter: Metrics.noteGutter) {
            linkHeader
            Hairline().padding(.horizontal, -Metrics.noteGutter)
            switch notes.phase {
            case .idle, .loading:
                NoteSkeleton()
            case .failed(let message):
                ErrorState(message: message, retry: { Task { await notes.reload() } })
            case .loaded:
                if notes.items.isEmpty {
                    FeedPlaceholder(
                        title: "아직 이 링크를 실은 노트가 없어요",
                        message: "링크를 담은 노트는 카드가 붙은 뒤에 여기 모여요.",
                        actionTitle: "인기 노트 보기",
                        action: {
                            NoteFeedChoice.shared.show(.trending)
                            TabRouter.shared.switchTo(1, reduceMotion: reduceMotion)
                        }
                    )
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
        .environment(\.noteFilterContext, notes.filterContext)
        .navigationTitle("링크")
        .noteTextLinks()
        .navigationBarTitleDisplayMode(.inline)
        .brandRefreshable { await notes.reload() }
        .task { if notes.items.isEmpty { await notes.reload() } }
    }

    private var linkHeader: some View {
        Button {
            if let link = URL(string: url) { openURL(link) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title?.isEmpty == false ? title! : url)
                        .typeScale(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: URL(string: url)?.host() ?? url)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                    .padding(.top, 4)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("linkNotes.open")
    }
}
