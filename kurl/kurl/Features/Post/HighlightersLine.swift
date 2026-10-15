import SwiftUI

struct HighlightersLine: View {
    let authors: [Author]
    let ring: Color

    @ScaledMetric(relativeTo: .footnote) private var unit: CGFloat = 1

    static func authors(of highlights: [HighlightView], isMine: (HighlightView) -> Bool) -> [Author] {
        var seen = Set<Int64>()
        return highlights.compactMap { h in
            guard let author = h.author ?? (isMine(h) ? viewer : nil),
                  seen.insert(author.id).inserted else { return nil }
            return author
        }
    }

    private static var viewer: Author? {
        guard let me = AuthStore.shared.me, let id = me.id else { return nil }
        return Author(id: id, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -6) {
                ForEach(authors.prefix(3)) { author in
                    AvatarView(author: author, size: 20 * unit)
                        .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
                }
            }
            .accessibilityHidden(true)
            summary
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: Text {
        guard authors.count == 1, let only = authors.first else {
            return Text("\(max(authors.count, 1))명이 그은 문장")
        }
        return only.id == AuthStore.shared.me?.id ? Text("내가 그은 문장") : Text("\(only.shownName)님이 그은 문장")
    }
}
