//
//  HighlightThreadSheet.swift
//  kurl
//

import SwiftUI

/// 하이라이트 답글 스레드(Are.na식 여백 대화) — 인용 + 작성자 메모(오프너) + 답글들 + 작성기.
/// 칠해진 하이라이트를 탭하면 뜬다. 본문 바깥은 조용하고(점·밑줄), 열면 풍부하게.
struct HighlightThreadSheet: View {
    let highlight: HighlightView
    let store: PostHighlightStore

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var replies: [HighlightReplyView] = []
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(highlight.quote)
                            .font(.system(size: 14 * unit))
                            .foregroundStyle(Palette.secondary)
                            .padding(.leading, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1).fill(Palette.accentSoft).frame(width: 2)
                            }

                        if let note = highlight.note, !note.isEmpty {
                            row(author: highlight.author?.username, date: highlight.createdAt, text: note)
                        }

                        ForEach(replies) { reply in
                            row(author: reply.author?.username, date: reply.createdAt, text: reply.body, replyId: reply.id)
                        }

                        if replies.isEmpty, (highlight.note?.isEmpty ?? true) {
                            Text("첫 답글을 남겨보세요.")
                                .font(.system(size: 13 * unit))
                                .foregroundStyle(Palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(20)
                }

                composer
            }
            .navigationTitle("하이라이트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await loadReplies() }
    }

    private func row(author: String?, date: Date?, text: String, replyId: Int64? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text("@\(author ?? "?")")
                    .font(.system(size: 13 * metaUnit, weight: .medium))
                    .foregroundStyle(Palette.ink)
                if let date {
                    Text(date.formatted(.dateTime.month().day()))
                        .font(.system(size: 12 * metaUnit))
                        .foregroundStyle(Palette.secondary)
                }
                if let replyId, AuthStore.shared.me?.id != nil, replyId > 0,
                   repliesAuthorIsMe(replyId) {
                    Button("삭제") { remove(replyId) }
                        .font(.system(size: 12 * metaUnit))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(busy)
                }
            }
            Text(text)
                .font(.system(size: 14 * unit))
                .foregroundStyle(Palette.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func repliesAuthorIsMe(_ replyId: Int64) -> Bool {
        guard let myId = AuthStore.shared.me?.id else { return false }
        return replies.first(where: { $0.id == replyId })?.author?.id == myId
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.hairline)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("답글 남기기…", text: $text, axis: .vertical)
                    .font(.system(size: 15 * unit))
                    .lineLimit(1...4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28 * unit))
                        .foregroundStyle(canSend ? Palette.accent : Palette.faint)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || busy)
                .accessibilityLabel(Text("답글 보내기"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func loadReplies() async {
        replies = (try? await HighlightsAPI.replies(highlightId: highlight.id)) ?? []
    }

    private func submit() {
        guard AuthStore.shared.isSignedIn else {
            dismiss()
            store.loginPrompt = true
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            _ = try? await HighlightsAPI.reply(highlightId: highlight.id, body: trimmed)
            text = ""
            await loadReplies()
            await store.load() // replyCount 갱신 → 본문 밑줄 표식
        }
    }

    private func remove(_ id: Int64) {
        busy = true
        Task {
            defer { busy = false }
            try? await HighlightsAPI.deleteReply(id: id)
            await loadReplies()
            await store.load()
        }
    }
}

/// 메모와 함께 하이라이트 — 선택 구간에 작성자의 여백 노트(스레드 오프너)를 달아 생성한다.
struct HighlightNoteComposerSheet: View {
    let draft: PostHighlightStore.NoteDraft
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var note = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.quote)
                    .font(.system(size: 13 * unit))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(3)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(Palette.accentSoft).frame(width: 2)
                    }
                TextField("이 부분에 대한 메모를 남겨보세요", text: $note, axis: .vertical)
                    .font(.system(size: 15 * unit))
                    .lineLimit(3...6)
                    .padding(13)
                    .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
            }
            .padding(20)
            .navigationTitle("메모 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { onSave(note); dismiss() }
                }
            }
        }
        .presentationDetents([.height(300), .medium])
    }
}
