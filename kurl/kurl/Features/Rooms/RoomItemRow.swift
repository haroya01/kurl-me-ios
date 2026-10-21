//
//  RoomItemRow.swift
//  kurl
//

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
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Palette.hairlineStrong)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(replies) { reply in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            AvatarView(author: reply.author, size: 18)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            (Text(reply.author.displayName ?? reply.author.username).fontWeight(.semibold)
                                + Text(verbatim: "  ")
                                + Text(reply.body))
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
    }
}
