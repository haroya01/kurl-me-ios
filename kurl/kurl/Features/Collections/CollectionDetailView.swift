//
//  CollectionDetailView.swift
//  kurl
//
//  컬렉션 상세 = 연결된 블록(글·하이라이트·노트)이 섞여 흐르는 채널. 각 연결은 큐레이터의
//  한 줄 이유를 단다 — 이게 단순 북마크와 컬렉션을 가르는 영혼(docs/collections-design.md).
//

import SwiftUI

struct CollectionDetailView: View {
    let collection: CollectionSummary
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            header
            Hairline().padding(.bottom, 4)

            LazyVStack(spacing: 0) {
                ForEach(Array(collection.items.enumerated()), id: \.element.id) { index, item in
                    connectionCell(item)
                        .modifier(QuietAppear(index: index))
                    if index < collection.items.count - 1 {
                        Hairline().padding(.leading, 14)
                    }
                }
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(collection.title)
                .typeScale(.featured)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let blurb = collection.blurb {
                Text(blurb)
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                AvatarView(author: collection.curator, size: 20)
                Text(collection.curator.username)
                    .foregroundStyle(Palette.ink)
                Text("·").foregroundStyle(Palette.faint)
                Image(systemName: collection.visibility.icon)
                    .font(.system(size: 11 * metaUnit, weight: .medium))
                Text(collection.visibility.label)
                Text("·").foregroundStyle(Palette.faint)
                Text("\(collection.count)개")
            }
            .font(.system(size: 13 * metaUnit, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }

    // MARK: 연결 한 칸 — 왼쪽 실(연결 신호) + [이유 한 줄] + 블록

    private func connectionCell(_ item: ConnectionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 연결의 실 — 이유와 블록이 "이어진 한 단위"임을 보이는 얇은 세로선(§10: 중립 잉크).
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.hairlineStrong)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 9) {
                Text(item.block.kindLabel)
                    .font(.system(size: 11 * metaUnit, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Palette.faint)

                if let why = item.why {
                    // 큐레이터의 한 줄 — 왜 이걸 여기 이었나. 이 컬렉션의 목소리.
                    Text(why)
                        .font(.system(size: 15 * unit, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                blockView(item.block)
            }
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func blockView(_ block: ConnectionBlock) -> some View {
        switch block {
        case let .post(title, excerpt, username, slug, tags):
            NavigationLink(value: Route.post(username: username, slug: slug)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(excerpt)
                        .font(.system(size: 14 * unit))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tag = tags.first {
                        Text("#\(tag)")
                            .font(.system(size: 12 * metaUnit, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(Palette.cardBg, in: RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous)
                        .strokeBorder(Palette.cardBorder, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(CardButtonStyle())

        case let .highlight(quote, postTitle, username, slug):
            NavigationLink(value: Route.post(username: username, slug: slug)) {
                VStack(alignment: .leading, spacing: 7) {
                    // 본문에서 칠한 그린 워시를 그대로 — 하이라이트는 어디서든 같은 얼굴.
                    Text(quote)
                        .font(.system(size: 15 * unit))
                        .foregroundStyle(Palette.body)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Palette.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                    Text(postTitle)
                        .font(.system(size: 13 * metaUnit, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .note(body):
            // 노트 = 제목 없는 생각 한 줄. 컬렉션이 집·맥락을 준다.
            Text(body)
                .font(.system(size: 16 * unit))
                .foregroundStyle(Palette.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
