//
//  Glass.swift
//  kurl
//

import SwiftUI
import Combine

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
/// 위계는 색 채움이 아니라 무게+잉크 대비가 진다 — 선택 알약은 유리 위로 살짝 들린 중립
/// 표면이고, matchedGeometry 로 오버슈트 없이 조용히 활주한다.
struct GlassSegmentSwitcher<T: Hashable & Identifiable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    /// 내비바(유리) 안에 들 때 true — 자기 유리 배경을 빼서 glass-on-glass(§1.4)를 피한다.
    var bare = false
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 14pt 고정이 Dynamic Type 를 무시하던 것 — 텍스트 스타일에 묶어 글자 크기 설정을 따른다.
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 14

    var body: some View {
        // 높이 ≈ 40pt — 헤더 영역의 유리 원형 버튼(벨 등)과 같은 키로 맞춘다.
        let row = HStack(spacing: 2) {
            ForEach(items) { item in
                let active = item == selection
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: labelSize, weight: active ? .semibold : .medium))
                        // 네 탭(최신·인기·추천·구독함)이 좁은 기기에서 줄바꿈돼 캡슐이 두꺼운
                        // 덩어리가 되던 것 — 한 줄 고정 + 긴 로케일(영어 Trending 등)은 살짝
                        // 축소해 잘림 없이 길쭉한 알약 유지.
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        // 위계는 무게+잉크 대비가 진다 — 선택=.primary, 비선택=.secondary. 유리 위
                        // 글자는 시맨틱 스타일이라 vibrancy 가 가독을 만든다(§1.2, slate 고정색 금지).
                        .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 13)
                        .padding(.vertical, bare ? 6 : 8)
                        .background {
                            if active {
                                // 선택 알약 = 유리 위로 살짝 들린 중립 표면(라이트 slate-200·다크 slate-700).
                                // 잉크 반전 슬래브의 소란을 걷고 은은한 lift 만 남긴다 — 위계는 라벨이 진다.
                                Capsule()
                                    .fill(Palette.hairlineStrong)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SegmentPressStyle())
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(bare ? 0 : 4)
        // 알약은 selection 이 어떻게 바뀌든(탭이든 스와이프든) 항상 미끄러진다 — 호출측
        // withAnimation 에 기대지 않고 자체 애니메이션으로 matchedGeometry 를 굴린다. 스프링
        // 오버슈트 없이 조용히 활주하도록 bounce 0 인 smooth 커브로 민다(§10.7 조용함).
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: selection)

        return Group {
            if bare {
                row // 내비바 유리가 배경 — 자기 유리는 얹지 않는다.
            } else {
                row
                    .glassEffect(.regular.interactive(), in: .capsule)
                    // 위쪽 모서리에 빛 한 가닥(아래로 사라지는 림) — 종이 위에서 판판하던 캡슐이
                    // "유리 한 겹"으로 읽히게 하는 글래스모피즘 신호. 히트테스트는 건드리지 않는다.
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.8)
                            .allowsHitTesting(false)
                    }
                    // 콘텐츠 위로 떠 있는 크롬 — 닿는 면 한 겹 + 옅은 앰비언트로 종이에서 들어 올린다.
                    .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
            }
        }
        // 분면 선택 = selection 햅틱 — 토글(.impact)·결과(.success)와 구분되는 세 번째 어휘.
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// 세그먼트 탭의 눌림 피드백 — 카드 press(스케일+스프링)와 같은 어휘의 작은 판. 좁은 타깃이라
/// 조금 더 눌러(0.94) 손끝에 잡히게 하고, reduce-motion 이면 스케일 대신 옅은 흐림으로 답한다.
/// 랜딩 tick 은 스위처의 selection 햅틱이 맡는다(press-down 햅틱은 중복이라 얹지 않는다).
private struct SegmentPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Press(configuration: configuration)
    }

    private struct Press: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.32, dampingFraction: 0.72),
                    value: configuration.isPressed)
        }
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
/// 설 자리를 만드는, 아주 옅은 브랜드 그린 메시. reduce-motion 이면 정지,
/// 저전력 모드·씬 비활성이면 마지막 프레임에서 멈춘다(장식이 배터리를 태우지 않게).
struct BrandMist: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        if reduceTransparency { Color.clear } else { mist }
    }

    /// 화면이 실제로 앞에 있고 여유 전력이 있을 때만 흐른다 — 앱 스위처·컨트롤 센터
    /// 뒤에서까지 20fps 재렌더를 돌릴 이유가 없다.
    private var paused: Bool {
        reduceMotion || lowPower || scenePhase != .active
    }

    private var mist: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { context in
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
        // 저전력 전환 알림은 임의 스레드에서 오므로 메인으로 옮겨 다시 읽는다.
        .onReceive(
            NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
