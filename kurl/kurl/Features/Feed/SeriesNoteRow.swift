//
//  SeriesNoteRow.swift
//  kurl
//

import SwiftUI

struct SeriesNoteRow: View {
    let note: FeedSeriesNote

    @ScaledMetric(relativeTo: .caption) private var markSize: CGFloat = 11

    private var warned: Bool { !(note.contentWarning ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    private var excerpt: Text {
        // 경고가 걸린 노트는 경고 문구만 — 가린 본문은 노트 상세에서 펼친다.
        warned
            ? Text("\(Image(systemName: "exclamationmark.triangle")) \(note.excerpt)")
            : Text(note.body.cleanedPreview)
    }

    var body: some View {
        NavigationLink(value: Route.note(id: note.id)) {
            RowLayout(
                excerpt: excerpt,
                excerptIsBody: !warned,
                read: PostReadStore.notes.isRead(note.id)
            ) {
                HStack(spacing: 6) {
                    Text(note.series.title)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    Text(verbatim: "·")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                    SeriesNoteMark(size: markSize, current: false)
                }
            } byline: {
                AuthorByline(author: note.author, date: note.createdAt)
            }
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "시리즈 \(note.series.title)의 노트, \(note.author.username) — \(warned ? note.excerpt : note.body)"))
        .accessibilityIdentifier("feed.seriesNote.\(note.id)")
    }
}
