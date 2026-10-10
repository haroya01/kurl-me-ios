//
//  HiddenRepliesView.swift
//  kurl
//

import SwiftUI

struct HiddenRepliesView: View {
    let noteId: Int64
    let threadWriter: Bool
    let onShown: (Note) -> Void

    @State private var replies: [Note]?
    @State private var failed: String?

    var body: some View {
        ReadingColumn(spacing: 0, background: Palette.readingBg, gutter: Metrics.noteGutter) {
            if let replies {
                if replies.isEmpty {
                    Text("숨긴 답글이 없어요")
                        .typeScale(.note)
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 56)
                } else {
                    ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                        NoteRowView(
                            note: reply,
                            onChange: { next in self.replies = self.replies?.map { $0.id == next.id ? next : $0 } },
                            onDelete: { id in self.replies?.removeAll { $0.id == id } },
                            threadModeration: moderation(of: reply))
                        if index < replies.count - 1 {
                            Hairline().padding(.horizontal, -Metrics.noteGutter)
                        }
                    }
                }
            } else if let failed {
                ErrorState(message: failed, retry: { Task { await load() } })
            } else {
                NoteSkeleton()
            }
        }
        .navigationTitle("숨긴 답글")
        .navigationBarTitleDisplayMode(.inline)
        .noteTextLinks()
        .brandRefreshable { await load() }
        .task { if replies == nil { await load() } }
    }

    private func moderation(of reply: Note) -> NoteThreadModeration? {
        guard threadWriter, reply.author.id != AuthStore.shared.me?.id else { return nil }
        return NoteThreadModeration { shown in
            guard shown.hidden != true else { return }
            replies?.removeAll { $0.id == shown.id }
            onShown(shown)
        }
    }

    private func load() async {
        do {
            replies = try await NoteAPI.hiddenReplies(of: noteId)
            failed = nil
        } catch {
            if replies == nil {
                failed = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }
}
