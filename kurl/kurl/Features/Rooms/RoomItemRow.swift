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

    var body: some View {
        switch item.kind {
        case .note(let note):
            NoteFeedItem(note: note, onChange: onReplace, onDelete: onRemove, onQuoted: onQuoted)
                .environment(\.insideRoom, showsRoom ? nil : note.room?.id)
        case .post(let post):
            VStack(alignment: .leading, spacing: 0) {
                if showsRoom, let room = post.room {
                    Button {
                        RoomsRouter.shared.open(room.id)
                    } label: {
                        Text("\(room.name) 방에서")
                            .typeScale(.meta)
                            .fontWeight(.medium)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 48 * min(scale, 1.8))
                    .padding(.top, 12)
                    .padding(.bottom, -8)
                }
                PostFeedRow(post: post)
            }
        }
    }
}
