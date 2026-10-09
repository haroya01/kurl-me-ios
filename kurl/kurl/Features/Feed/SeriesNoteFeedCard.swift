//
//  SeriesNoteFeedCard.swift
//  kurl
//
//  구독함에 끼는 구독 시리즈의 노트 — 글 카드(텍스트 변형)와 같은 종이·그림자에, 제목 자리를
//  "어느 시리즈의 노트인지"가 맡는다. 탭하면 노트 상세(시리즈 배너가 그 자리를 이어 준다).
//

import SwiftUI

struct SeriesNoteFeedCard: View {
    let note: FeedSeriesNote

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption) private var markSize: CGFloat = 11

    private var warned: Bool { !(note.contentWarning ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationLink(value: Route.note(id: note.id)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    KurlMark(drawn: [true, true, true], tint: Palette.secondary)
                        .frame(width: 16, height: 10)
                        .accessibilityHidden(true)
                    Text(note.series.title)
                        .typeScale(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.heading)
                        .lineLimit(1)
                    Text(verbatim: "·")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                    SeriesNoteMark(size: markSize, current: false)
                }
                // 경고가 걸린 노트는 경고 문구만 — 가린 본문은 노트 상세에서 펼친다.
                if warned {
                    Label(note.excerpt, systemImage: "exclamationmark.triangle")
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                } else {
                    Text(note.body.cleanedPreview)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    AvatarView(author: note.author, size: 18)
                    Text(note.author.username)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    if let date = note.createdAt {
                        Text(verbatim: "·").foregroundStyle(Palette.faint)
                        Text(date.relativeShort)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .padding(.top, 2)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.cardBg, in: RoundedRectangle(cornerRadius: BlogCard.radius, style: .continuous))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: BlogCard.radius, style: .continuous)
                        .strokeBorder(Palette.cardBorder, lineWidth: 1)
                }
            }
            .cardShadow()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "시리즈 \(note.series.title)의 노트, \(note.author.username) — \(warned ? note.excerpt : note.body)"))
        .accessibilityIdentifier("feed.seriesNote.\(note.id)")
    }
}
