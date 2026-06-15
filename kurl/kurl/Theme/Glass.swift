//
//  Glass.swift
//  kurl
//

import SwiftUI

// MARK: 유리 캡슐 토글 — 팔로우·구독·정렬 칩이 공유하는 문법

extension View {
    /// prominent = 흰 라벨 + 그린(700) 유리, 아니면 맑은 유리로 가라앉는다.
    /// 켜짐/꺼짐이 아니라 "지금 주행동인가"로 고른다 — 팔로우 전이 prominent, 팔로잉은 조용히.
    /// 투명도 감소가 켜지면 유리를 솔리드로 — 위계(그린 채움 vs 차분한 면)는 그대로 성립(§1.7).
    func glassCapsule(prominent: Bool) -> some View {
        modifier(GlassCapsule(prominent: prominent))
    }

    /// 셀렉터(기간·정렬 칩 등) 선택 표시 — 형광 초록(주 액션 색)과 구분되는 중립 잉크 알약.
    /// 선택 라벨은 배경색으로 두면(반전) 다크모드에서도 대비가 선다. §10 색 규율: 초록은 주 액션만.
    func selectorPill(selected: Bool) -> some View {
        background(selected ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.clear), in: Capsule())
    }
}

private struct GlassCapsule: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                prominent ? Palette.accentFill : Palette.cardBg, in: Capsule())
        } else {
            content.glassEffect(
                prominent
                    ? .regular.tint(GlassTokens.prominentTint).interactive()
                    : .regular.interactive(),
                in: .capsule)
        }
    }
}

// MARK: 떠 있는 유리 세그먼트 — 피드 소스 전환

/// 상단 고정 스트립을 대체하는 떠 있는 유리 캡슐. 콘텐츠는 이 밑으로 흐른다.
/// 활성 thumb 은 그린 700 채움(흰 라벨 규칙) — matchedGeometry 로 액체처럼 미끄러진다.
struct GlassSegmentSwitcher<T: Hashable & Identifiable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    /// 내비바(유리) 안에 들 때 true — 자기 유리 배경을 빼서 glass-on-glass(§1.4)를 피한다.
    var bare = false
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 높이 ≈ 40pt — 헤더 영역의 유리 원형 버튼(벨 등)과 같은 키로 맞춘다.
        let row = HStack(spacing: 2) {
            ForEach(items) { item in
                let active = item == selection
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: 14, weight: active ? .semibold : .medium))
                        // 네 탭(최신·인기·추천·구독함)이 좁은 기기에서 줄바꿈돼 캡슐이 두꺼운
                        // 덩어리가 되던 것 — 한 줄 고정 + 긴 로케일(영어 Trending 등)은 살짝
                        // 축소해 잘림 없이 길쭉한 알약 유지.
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        // 선택=중립 잉크 알약 + 반전 라벨(배경색). 형광 초록 candy를 걷는다(§10 색 규율).
                        .foregroundStyle(active
                            ? AnyShapeStyle(Color(uiColor: .systemBackground))
                            : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 13)
                        .padding(.vertical, bare ? 6 : 8)
                        .background {
                            if active {
                                Capsule()
                                    .fill(Palette.ink)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(bare ? 0 : 4)
        // 알약(thumb)은 selection 이 어떻게 바뀌든(탭이든 스와이프든) 항상 미끄러진다 —
        // 호출측 withAnimation 에 기대지 않고 자체 애니메이션으로 matchedGeometry 를 굴린다.
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selection)

        return Group {
            if bare {
                row // 내비바 유리가 배경 — 자기 유리는 얹지 않는다.
            } else {
                row.glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        // 분면 선택 = selection 햅틱 — 토글(.impact)·결과(.success)와 구분되는 세 번째 어휘.
        .sensoryFeedback(.selection, trigger: selection)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency { Color.clear } else { mist }
    }

    private var mist: some View {
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
