//
//  BlogCard.swift
//  kurl
//

import SwiftUI

/// 발견(browse) 면의 글 카드 — 웹 DiscoveryCard 문법을 그대로 옮긴다.
/// 카드는 §10.1 읽기 컬럼 불변식의 명시적 예외(browse 전용): 피드·검색만 카드,
/// 작가/태그/시리즈 읽기 면은 여전히 FeedRow 목록 행.
///
/// 변형은 결정적(같은 글은 항상 같은 모양):
/// - ogImageUrl 있음 → cover: 사진이 카드 전체 배경, 흰 타이포 오버레이 + 가독 scrim
/// - 없음 → text: 흰(다크: slate-900) 타이포 카드, 소개글은 있을 때만
/// 이미지 강제 없음(§10.4). 모바일 전폭 1열이라 featured 도 4:3 고정 —
/// 웹의 featured 3:4 는 sm+ 메이슨리 앵커용이고, 전폭 3:4 는 첫 화면을 통째로 먹는다(#707).
struct BlogCard: View {
    let item: FeedItem
    var featured = false
    /// 이 글이 담긴 공개 컬렉션(소속 한 올) — 있을 때만 카드 아래 한 줄이 선다. 배치로 채워져 곁에서 도착한다.
    var belonging: [CollectionSummary] = []

    @Environment(\.colorScheme) private var colorScheme

    /// 카드 모서리 — 유리 시대의 연속 곡률(§1.5). 하단 유리 띠와 반드시 같은 값.
    static let radius: CGFloat = Metrics.radiusCard

    var body: some View {
        Group {
            if let urlString = item.ogImageUrl, let url = URL(string: urlString) {
                cover(url: url)
            } else {
                textCard
            }
        }
        // 카드 전체를 한 장의 탭 면으로 — 커버 하단 타이포 띠가 탭에서 빠져(제목·메타를 눌러도
        // 글이 안 열림) 있던 것을 카드 전면 히트 셰이프로 묶는다(태그 칩은 자기 링크 유지).
        .contentShape(.rect)
        // 북마크한 글이면 우상단에 북마크 표식 — 피드에서 "이미 담아 둔 글"이 한눈에 보인다.
        .overlay(alignment: .topTrailing) {
            if BookmarkStore.shared.contains(item.id) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.ogImageUrl != nil ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.accentMarker))
                    .shadow(color: .black.opacity(item.ogImageUrl != nil ? 0.35 : 0), radius: 3, y: 1)
                    .padding(12)
                    .accessibilityLabel("북마크됨")
            }
        }
        .onAppear {
            Task { await BookmarkStore.shared.hydrateIfNeeded() }
            Task { await BlockStore.shared.hydrateIfNeeded() }
        }
    }

    // MARK: cover — 사진이 카드 전체 배경

    private func cover(url: URL) -> some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                RemoteImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Palette.hairline)
                    }
                }
                // 톤 하모나이즈: 저채도 + 그린 베일 — 피드의 사진들이 한 결로 가라앉는다(#692-693).
                .saturation(0.85)
            }
            .overlay(Palette.coverVeil)
            .overlay(alignment: .top) {
                // 상단 scrim — 좌상단 태그/featured 뱃지 가독용.
                LinearGradient(
                    colors: [.black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 64)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    if featured { FeaturedBadge(over: true) }
                    if let tag = item.renderableTags.first {
                        // 칩처럼 보이면 칩처럼 동작해야 한다 — 탭 = 태그 피드.
                        NavigationLink(value: Route.tag(tag)) {
                            Text("#\(tag)")
                                .typeScale(.meta)
                                .foregroundStyle(.white)
                                .expandTapTarget(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .overlay(alignment: .bottom) {
                // 하단 타이포 띠 = 맑은 유리 — 카드 안 유리의 유일한 예외(AGENTS.md §1.5).
                // 무거운 그라데이션 대신 사진이 띠 뒤로 비치고, 가독은 mediaScrim 틴트가 잡는다.
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .typeScale(featured ? .featured : .title)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    CardMeta(item: item, over: true)
                    if !belonging.isEmpty {
                        BelongingLine(collections: belonging, over: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(CoverBandSurface())
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay {
                // 어두운 커버 가장자리의 유리 같은 1px 빛 테두리.
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .cardShadow()
    }

    // MARK: text — 이미지 없이 타이포가 주인인 카드

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if featured || item.renderableTags.first != nil {
                HStack(spacing: 8) {
                    if featured { FeaturedBadge(over: false) }
                    if let tag = item.renderableTags.first {
                        NavigationLink(value: Route.tag(tag)) {
                            Text("#\(tag)")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                                .expandTapTarget(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(item.title)
                .typeScale(featured ? .featured : .title)
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CardMeta(item: item, over: false)
            if !belonging.isEmpty {
                BelongingLine(collections: belonging)
                    .padding(.top, 1)
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.cardBg, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay {
            // 라이트는 그림자만으로 선다(보더 = 웹 상자 느낌) — 다크는 그림자가 죽어 보더 유지.
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
        }
        .cardShadow()
    }
}

/// featured(오늘의 글) 신호 — 위계는 큰 제목(typeScale .featured)이 지므로 라벨은 조용한 eyebrow.
/// 초록 점은 빼고 muted 로(초록=주액션·데이터 전용). cover 위에선 흰 pill 로 가독 확보.
private struct FeaturedBadge: View {
    let over: Bool
    /// "오늘의 글" 배지 — 사다리에 딱 맞는 롤이 없어(고유 자간) 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 11

    var body: some View {
        Text("오늘의 글")
            .font(.system(size: badgeSize, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(over ? Palette.ink : Palette.secondary)
            .padding(.horizontal, over ? 9 : 0)
            .padding(.vertical, over ? 4 : 0)
            .background {
                if over {
                    Capsule().fill(.white.opacity(0.9))
                }
            }
    }
}

/// 아바타 · 작가 · 날짜 · ♥좋아요(>0) — 웹 CardMeta 와 동일 정보, over = 커버 위 흰 변형.
private struct CardMeta: View {
    let item: FeedItem
    let over: Bool

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(author: item.author, size: 16)
            Text(item.author.username)
                .fontWeight(.medium)
                .lineLimit(1)
            if let date = item.publishedAt {
                Text("·").foregroundStyle(dim)
                // browse 면 시간 문법 통일 — 행·허브와 같은 상대시간(상세만 절대 날짜).
                Text(date.relativeShort)
            }
            if item.likeCount > 0 {
                Text("·").foregroundStyle(dim)
                HStack(spacing: 3) {
                    Image(systemName: "heart")
                        .font(.system(size: 10))
                        .foregroundStyle(tone)
                    Text("\(item.likeCount)")
                }
            }
        }
        .typeScale(.meta)
        .foregroundStyle(tone)
    }

    // 유리 띠 + 0.40 스크림 위 12pt — 밝은 커버에서 0.85 는 ~2.3:1 로 깎였다. 텍스트는 순백.
    private var tone: Color { over ? .white : Palette.secondary }
    private var dim: Color { over ? .white.opacity(0.65) : Palette.faint }
}

/// 소속 한 올 — "이 글이 담긴 곳"(§0 발견 = 큐레이터 연결). 종이 카드 아래 조용한 한 줄:
/// ↳ 글리프(그린 한 가닥, §10.3 비텍스트 마커 = accent)에 담긴 공개 컬렉션 제목 + 그 외 몇 개.
/// 같은 글이 여러 컬렉션에 걸려 맥락이 겹친다는 §0 서사를 카드에서 조용히 드러낸다. 소속이 없으면 이 줄은
/// 그려지지 않는다(호출측 가드). 커버 위(over)에선 유리 규율대로 그린을 빼고 흰 위계만 쓴다(§1.2).
private struct BelongingLine: View {
    let collections: [CollectionSummary]
    var over: Bool = false

    /// ↳ 글리프 — .footnote 옆에서 균형 잡히게 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 10

    private var lead: CollectionSummary? { collections.first }

    var body: some View {
        if let lead {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                // 그린 한 가닥은 글리프에만(§10.3 비텍스트 마커 = accent 600) — 카피는 조용한 슬레이트로
                // 흘러 로케일마다 조사·어순이 자연스럽게 붙는다(한 Text = 한 번역 문자열).
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: glyph, weight: .semibold))
                    .foregroundStyle(marker)
                caption(title: lead.title)
                    .foregroundStyle(textTone)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .typeScale(.footnote)
            .accessibilityElement(children: .combine)
        }
    }

    /// "'제목'에 담김" / "'제목' 외 N개 컬렉션에 담김" — 한 번역 문자열로, 로케일이 조사·어순을 소유한다.
    private func caption(title: String) -> Text {
        let others = collections.count - 1
        if others == 0 {
            return Text("‘\(title)’에 담김")
        }
        return Text("‘\(title)’ 외 \(others)개 컬렉션에 담김")
    }

    // 종이 = 그린 한 가닥(글리프=accent 600), 카피는 슬레이트. 커버 위 = 유리 규율상 흰 위계만(§1.2).
    private var marker: Color { over ? .white : Palette.accent }
    private var textTone: Color { over ? .white.opacity(0.85) : Palette.secondary }
}

/// 카드 다층 그림자 — 닿는 면 1px + 멀리 퍼지는 ambient. 라이트의 무보더 카드를
/// 이 두 겹이 종이에서 들어 올린다(웹 CARD_SHADOW 의 유리 시대 보정).
private struct CardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }
}

extension View {
    func cardShadow() -> some View { modifier(CardShadow()) }
}

/// 카드 press — 행 하이라이트 대신 카드가 살짝 가라앉았다 스프링으로 돌아온다.
/// reduce-motion 이면 스프링 바운스를 걷고 조용한 딤으로만 눌린다(§1.6 모핑·바운스 끔).
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Press(configuration: configuration)
    }

    private struct Press: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.82 : 1)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.32, dampingFraction: 0.72),
                    value: configuration.isPressed)
        }
    }
}


/// 커버 하단 타이포 띠의 표면 — 평소엔 맑은 유리+스크림, 투명도 감소가 켜지면
/// 비치는 사진 대신 진한 솔리드 스크림으로(가독이 설정보다 우선).
private struct CoverBandSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: UnevenRoundedRectangle {
        // 하단은 카드 곡률(20)을 따르고, 사진과 만나는 위쪽 모서리도 각지지 않게 살짝 둥글린다
        // (radiusMini) — 유리 띠가 종이 위 알약처럼 얹히도록.
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: Metrics.radiusMini, bottomLeading: BlogCard.radius,
                bottomTrailing: BlogCard.radius, topTrailing: Metrics.radiusMini),
            style: .continuous)
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.black.opacity(0.72), in: shape)
        } else {
            content.glassEffect(.clear.tint(GlassTokens.mediaScrim), in: shape)
        }
    }
}
