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
                // 콘텐츠가 edge-to-edge로 흐른다 — 피드 탭과 같은 결(고정 "발견" 타이틀 ❌).
                Color.clear.frame(height: 8)
                LazyVStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        ConnectionEventCard(event: event)
                            .modifier(QuietAppear(index: index))
                        if index < events.count - 1 {
                            Hairline().padding(.vertical, 10)
                        }
                    }
                }
            }
            // 고정 스트립 대신 콘텐츠가 유리 크롬 밑으로 흐른다 — 상단 라벨은 탭바 아이콘이 맡는다.
            .toolbar(.hidden, for: .navigationBar)
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
        VStack(alignment: .leading, spacing: 12) {
            // 귀속 = 조용히. 누가·언제만(broadcast 아니라 connect 라는 건 아래 eyebrow 가 말한다).
            HStack(spacing: 7) {
                AvatarView(author: event.curator, size: 22)
                Text(event.curator.username)
                    .font(.system(size: 13 * metaUnit, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                Text("·").foregroundStyle(Palette.faint)
                Text(event.connectedAt.relativeShort)
                    .font(.system(size: 13 * metaUnit))
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 0)
            }

            // 컬렉션 eyebrow — "…에 연결" 이라는 동사를 탭 가능한 채널 칩으로. 한 연결에서
            // 그 채널 전체로 이어지는 문(§0 connect). 초록은 데이터 링크라 link 톤 허용.
            NavigationLink(value: collectionTarget) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10 * metaUnit, weight: .bold))
                    Text(event.collectionTitle)
                        .font(.system(size: 12 * metaUnit, weight: .bold))
                        .tracking(0.3)
                    Text("에 연결")
                        .font(.system(size: 12 * metaUnit, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
                .foregroundStyle(Palette.link)
                .expandTapTarget(6)
            }
            .buttonStyle(.plain)

            // 큐레이터의 한 줄 = 히어로. 이 흐름이 알고리즘 피드가 아니라 사람의 큐레이션이라는
            // 가장 또렷한 신호. 없으면(이유 안 단 연결) 블록이 곧장 히어로가 된다.
            if let why = event.why {
                Text(why)
                    .font(.system(size: 17 * unit, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BlockPreview(block: event.block)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
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
