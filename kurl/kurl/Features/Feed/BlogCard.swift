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

    var body: some View {
        Group {
            if let urlString = item.ogImageUrl, let url = URL(string: urlString) {
                cover(url: url)
            } else {
                textCard
            }
        }
    }

    // MARK: cover — 사진이 카드 전체 배경

    private func cover(url: URL) -> some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Palette.hairline)
                }
                // 톤 하모나이즈: 저채도 + 그린 베일 — 피드의 사진들이 한 결로 가라앉는다(#692-693).
                .saturation(0.85)
            }
            .overlay(Palette.coverVeil)
            .overlay {
                // 하단 가독 scrim — 제목·메타가 어떤 사진 위에서도 읽히게.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.70), location: 0),
                        .init(color: .black.opacity(0.10), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            }
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
                    if let tag = item.tags.first {
                        Text("#\(tag)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(14)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: featured ? 20 : 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    CardMeta(item: item, over: true)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                // 어두운 커버 가장자리의 유리 같은 1px 빛 테두리.
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .cardShadow()
    }

    // MARK: text — 이미지 없이 타이포가 주인인 카드

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if featured || item.tags.first != nil {
                HStack(spacing: 8) {
                    if featured { FeaturedBadge(over: false) }
                    if let tag = item.tags.first {
                        Text("#\(tag)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            Text(item.title)
                .font(.system(size: featured ? 19 : 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CardMeta(item: item, over: false)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardBg, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
        .cardShadow()
    }
}

/// featured(오늘의 글) 신호 — 그린 점 + 라벨. cover 위에선 흰 pill 로 가독 확보.
private struct FeaturedBadge: View {
    let over: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(over ? Palette.accent : Palette.accent)
                .frame(width: 6, height: 6)
            Text("오늘의 글")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(over ? Color(hex: 0x0F172A) : Palette.link)
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
                Text(date.formatted(.dateTime.month().day()))
            }
            if item.likeCount > 0 {
                Text("·").foregroundStyle(dim)
                HStack(spacing: 3) {
                    Image(systemName: "heart")
                        .font(.system(size: 10))
                        .foregroundStyle(over ? tone : Palette.accentMarker)
                    Text("\(item.likeCount)")
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(tone)
    }

    private var tone: Color { over ? .white.opacity(0.85) : Palette.secondary }
    private var dim: Color { over ? .white.opacity(0.5) : Palette.faint }
}

/// 카드 다층 그림자 — 닿는 면 1px + 퍼지는 ambient(웹 CARD_SHADOW 등가).
private struct CardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.10), radius: 10, y: 6)
    }
}

extension View {
    func cardShadow() -> some View { modifier(CardShadow()) }
}

/// 카드 press — 행 하이라이트 대신 카드가 살짝 가라앉는다.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
