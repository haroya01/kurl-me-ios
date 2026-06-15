//
//  DiscoverView.swift
//  kurl
//
//  발견 = 읽기의 연결 그래프 홈(§0). 1차 표면 = 큐레이터 연결 흐름("누가 무엇을 어느 컬렉션에
//  이었나 + 왜"). 기존 릴스 덱은 "읽기 모드"로 흡수 — 선택 없이 몰입해 바로 읽는 보조 모드.
//  broadcast 아니라 큐레이션을 따라간다(docs/collections-design.md).
//

import SwiftUI

struct DiscoverView: View {
    @State private var events = CollectionsMock.discoverFeed
    @State private var showDeck = false
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        ConnectionEventCard(event: event)
                            .modifier(QuietAppear(index: index))
                        if index < events.count - 1 {
                            Hairline().padding(.vertical, 4)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .navigationTitle("발견")
            .navigationBarTitleDisplayMode(.inline)
            // "읽기 모드" — 선택 없이 바로 읽는 몰입 덱(릴스형)을 보조 모드로 띄운다.
            .safeAreaInset(edge: .bottom) {
                Button { showDeck = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 14 * unit, weight: .semibold))
                        Text("읽기 모드")
                            .font(.system(size: 15 * unit, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
                .accessibilityLabel(Text("읽기 모드 — 바로 읽는 덱"))
            }
            .navigationDestination(for: CollectionSummary.self) { CollectionDetailView(collection: $0) }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .fullScreenCover(isPresented: $showDeck) {
            DeckModeContainer { showDeck = false }
        }
    }
}

/// 큐레이터 연결 한 장 — 누가(아바타+이름) → 어느 컬렉션에 → [왜 한 줄] → 블록.
private struct ConnectionEventCard: View {
    let event: ConnectionEvent
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // 귀속 줄 — broadcast("…님이 게시함")가 아니라 connect("…에 연결했어요").
            HStack(spacing: 8) {
                AvatarView(author: event.curator, size: 24)
                (Text(event.curator.username).foregroundStyle(Palette.ink)
                    + Text(" 님이 ").foregroundStyle(Palette.secondary)
                    + Text(event.collectionTitle).foregroundStyle(Palette.ink)
                    + Text(" 에 연결했어요").foregroundStyle(Palette.secondary))
                    .font(.system(size: 14 * metaUnit, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(event.connectedAt.relativeShort)
                    .font(.system(size: 12 * metaUnit))
                    .foregroundStyle(Palette.faint)
            }

            if let why = event.why {
                Text(why)
                    .font(.system(size: 15 * unit, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BlockPreview(block: event.block)

            // 컬렉션으로 — 한 연결에서 그 채널 전체로 이어지는 문.
            NavigationLink(value: collectionTarget) {
                HStack(spacing: 3) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11 * metaUnit, weight: .semibold))
                    Text(event.collectionTitle)
                        .font(.system(size: 13 * metaUnit, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9 * metaUnit, weight: .semibold))
                }
                .foregroundStyle(Palette.link)
                .expandTapTarget(6)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    // 프로토타입 — 흐름의 컬렉션을 목 상세로 잇는다(슬러그 매칭 대신 대표 컬렉션).
    private var collectionTarget: CollectionSummary {
        CollectionsMock.mine.first { $0.id == event.collectionId } ?? CollectionsMock.slowThinking
    }
}

/// 연결된 블록 미리보기 — 글 미니카드 · 하이라이트 그린워시 · 노트. 컬렉션 상세와 같은 얼굴.
struct BlockPreview: View {
    let block: ConnectionBlock
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
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
            Text(body)
                .font(.system(size: 16 * unit))
                .foregroundStyle(Palette.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "읽기 모드" 컨테이너 — 기존 릴스 덱을 그대로 띄우고, 닫기 핀만 얹는다.
private struct DeckModeContainer: View {
    let onClose: () -> Void

    var body: some View {
        DiscoverDeckView()
            .overlay(alignment: .topLeading) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(.leading, Metrics.gutter)
                .padding(.top, 4)
                .accessibilityLabel(Text("읽기 모드 닫기"))
            }
    }
}
