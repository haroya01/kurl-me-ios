//
//  Glass.swift
//  kurl
//

import SwiftUI

// MARK: 유리 캡슐 토글 — 팔로우·구독·정렬 칩이 공유하는 문법

extension View {
    /// prominent = 흰 라벨 + 그린(700) 유리, 아니면 맑은 유리로 가라앉는다.
    /// 켜짐/꺼짐이 아니라 "지금 주행동인가"로 고른다 — 팔로우 전이 prominent, 팔로잉은 조용히.
    func glassCapsule(prominent: Bool) -> some View {
        glassEffect(
            prominent
                ? .regular.tint(GlassTokens.prominentTint).interactive()
                : .regular.interactive(),
            in: .capsule)
    }
}

// MARK: 떠 있는 유리 세그먼트 — 피드 소스 전환

/// 상단 고정 스트립을 대체하는 떠 있는 유리 캡슐. 콘텐츠는 이 밑으로 흐른다.
/// 활성 thumb 은 그린 700 채움(흰 라벨 규칙) — matchedGeometry 로 액체처럼 미끄러진다.
struct GlassSegmentSwitcher<T: Hashable & Identifiable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let active = item == selection
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { selection = item }
                } label: {
                    Text(label(item))
                        .font(.system(size: 14, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if active {
                                Capsule()
                                    .fill(GlassTokens.prominentTint)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(3)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: 떠 있는 주행동 버튼

/// 유리 원판 FAB — 흰 심볼 + 브랜드 그린 틴트. 탭바 위 우하단에 띄운다.
struct GlassFAB: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(GlassTokens.prominentTint).interactive(), in: .circle)
        .accessibilityLabel(Text(label))
    }
}

// MARK: 조용한 그린 안개 — 유리가 설 수 있는 배경

/// 유리는 뒤에 흐르는 것이 있을 때만 유리다 — 빈 종이 위 유리 패널(계정 정체 카드)이
/// 설 자리를 만드는, 아주 옅은 브랜드 그린 메시. reduce-motion 이면 정지.
struct BrandMist: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.18
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5],
                    [0.5 + Float(sin(t)) * 0.18, 0.5 + Float(cos(t * 0.8)) * 0.14],
                    [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    .clear, Palette.accent.opacity(0.05), .clear,
                    Palette.accent.opacity(0.08), Palette.accentSoft.opacity(0.16), Palette.accent.opacity(0.06),
                    .clear, Palette.accent.opacity(0.04), .clear,
                ]
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
