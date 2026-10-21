import SwiftUI

struct RoomItemRow: View {
    let item: HomeFeedItem
    var showsRoom = false
    var onReplace: (Note) -> Void = { _ in }
    var onRemove: (Int64) -> Void = { _ in }
    var onQuoted: (Note) -> Void = { _ in }

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var maxReplies = 2

    @Environment(\.openNoteRoute) private var openNoteRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if !item.replies.isEmpty {
                RoomReplyPreview(
                    replies: Array(item.replies.prefix(maxReplies)),
                    total: max(item.replyTotal, Int64(item.replies.count)),
                    parentKey: item.note.map { NoteTranslation.key($0) },
                    open: openTarget)
                    .padding(.leading, 48 * min(scale, 1.8))
                    .padding(.bottom, 12)
                    .padding(.top, -4)
            }
        }
    }

    private func openTarget() {
        switch item.kind {
        case .note(let note): openNoteRoute?(.note(id: note.id))
        case .post(let post): openNoteRoute?(.post(username: post.author.username, slug: post.slug))
        }
    }

    @ViewBuilder
    private var row: some View {
        switch item.kind {
        case .note(let note):
            NoteFeedItem(note: note, onChange: onReplace, onDelete: onRemove, onQuoted: onQuoted)
                .environment(\.insideRoom, showsRoom ? nil : note.room?.id)
        case .post(let post):
            PostFeedRow(post: post)
                .environment(\.insideRoom, showsRoom ? nil : post.room?.id)
        }
    }

}

struct RoomReplyPreview: View {
    let replies: [HomeFeedItem.ReplyPreview]
    let total: Int64
    var parentKey: String?
    let open: () -> Void

    @State private var translations = ContentTranslations.shared
    @State private var request: TranslationRequest?

    private var bodies: [String] { replies.map(\.body) }

    private var key: String? {
        parentKey.map { "replies-\($0)-\(replies.map { String($0.id) }.joined(separator: ","))" }
    }

    private var parentShown: Bool {
        parentKey.map { translations.phases[$0] == .shown } ?? false
    }

    private var shownBodies: [String] {
        guard parentShown, let key, let done = translations.shown(key) else { return bodies }
        return NoteTranslation.apply(done, replies: bodies)
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Palette.hairlineStrong)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(zip(replies, shownBodies)), id: \.0.id) { reply, body in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            AvatarView(author: reply.author, size: 18)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            (Text(reply.author.displayName ?? reply.author.username).fontWeight(.semibold)
                                + Text(verbatim: "  ")
                                + Text(body))
                                .typeScale(.lede)
                                .foregroundStyle(Palette.body)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    if total > Int64(replies.count) {
                        Text("댓글 \(total)개 모두 보기")
                            .typeScale(.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room.replies")
        .translationRunner($request)
        .onChange(of: parentShown, initial: true) { _, shown in
            if shown { translate() }
        }
    }

    private func translate() {
        guard let key, request == nil, translations.phases[key] == nil, !translations.showCached(key) else { return }
        let texts = NoteTranslation.requests(replies: bodies)
        guard !texts.isEmpty,
              let source = TranslationGate.source(declared: nil, text: texts.joined(separator: " "))
        else { return }
        let next = TranslationRequest(key: key, source: source, target: TranslationGate.target(), texts: texts)
        translations.begin(next)
        request = next
    }
}
