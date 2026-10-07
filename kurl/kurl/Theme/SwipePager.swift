//
//  SwipePager.swift
//  kurl
//

import SwiftUI

/// 피드 탭을 좌우로 넘기는 필름스트립 — 블로그·노트 탭이 같은 손맛으로 넘어가게 한 벌로 둔다.
///
/// 페이지형 TabView(UIPageViewController) 중첩은 Liquid Glass 가 활성 탭의 스크롤뷰를 못 찾게 만들어
/// 하단 바 아래로 콘텐츠가 흐르지 않고 스크롤 축소도 안 걸렸다. 페이지를 ZStack 으로 살려두고(데이터·
/// 스크롤 위치 유지) 좌우 스와이프는 제스처로 직접 — ScrollView 가 탭 콘텐츠의 직계가 된다.
/// 선택 ±1 칸만 그려 곧 보일 페이지만 첫 로드한다(`warm`).
struct SwipePager<Tab: Hashable & Identifiable, Page: View>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    @ViewBuilder let page: (_ tab: Tab, _ active: Bool, _ warm: Bool) -> Page

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 손가락을 따라 끌린 거리 — 인접 페이지는 한 폭 옆에서 따라 들어온다.
    @State private var dragX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    /// 스와이프가 방금 selection 을 확정했음을 onChange 에 알린다 — 스와이프 경로는 dragX 를 스스로
    /// 보정해 슬라이드하므로, 뒤이어 발화하는 onChange 가 같은 전환을 한 번 더 슬라이드시키지 않게.
    @State private var swipeCommitted = false
    /// 페이지 안의 가로 스크롤(사진 넘기기)이 잡은 드래그는 페이지를 넘기지 않는다 — 둘이 같이 움직이던 것.
    @State private var gate = SwipePagerGate()
    @State private var blocked = false

    var body: some View {
        ZStack {
            ForEach(tabs) { tab in
                page(tab, tab == selection, visible(tab))
                    // 슬라이드 중 중앙을 벗어난 분면은 살짝 가라앉는다 — 옆 칸이 "뒤에 있다"는 얕은 깊이.
                    .opacity(opacity(tab))
                    // 드래그 중엔 페이지 콘텐츠를 비활성화 — 카드가 손가락과 함께 움직여 탭이 안 취소되던 것.
                    .disabled(dragX != 0)
                    .allowsHitTesting(tab == selection)
                    .accessibilityHidden(tab != selection)
                    .offset(x: offset(tab))
                    .environment(\.swipePagerGate, gate)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .simultaneousGesture(drag)
        // 스위처를 눌러 바꿔도 스와이프처럼 미끄러진다 — 비슷한 카드 목록이 스냅으로 갈리면 전환이
        // 안 느껴졌다. 바인딩을 withAnimation 으로 감싸지 않는다 — 스위처 알약 활주와 충돌(함정).
        .onChange(of: selection) { old, new in
            if swipeCommitted {
                swipeCommitted = false
                return
            }
            guard !reduceMotion, containerWidth > 0,
                  let from = tabs.firstIndex(of: old),
                  let to = tabs.firstIndex(of: new), from != to else { return }
            dragX = CGFloat(to - from) * containerWidth
            withAnimation(.snappy(duration: 0.32)) { dragX = 0 }
        }
    }

    private var selectionIndex: Int { tabs.firstIndex(of: selection) ?? 0 }
    private func index(_ tab: Tab) -> Int { tabs.firstIndex(of: tab) ?? 0 }

    private func visible(_ tab: Tab) -> Bool { abs(index(tab) - selectionIndex) <= 1 }

    /// 각 페이지를 (자기 인덱스 − 선택 인덱스)×폭 + dragX 에 둔다. 전환 때 선택 인덱스와 dragX 를 같은
    /// 프레임에 맞바꿔(±폭이 상쇄) 시각이 연속이라 점프·깜빡임이 없다.
    private func offset(_ tab: Tab) -> CGFloat {
        CGFloat(index(tab) - selectionIndex) * containerWidth + dragX
    }

    private func opacity(_ tab: Tab) -> Double {
        guard visible(tab) else { return 0 }
        guard !reduceMotion, containerWidth > 0 else { return 1 }
        return 1 - 0.15 * min(1, abs(offset(tab)) / containerWidth)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if gate.held { blocked = true }
                if blocked {
                    if dragX != 0 { dragX = 0 }
                    return
                }
                guard !reduceMotion,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                var dx = value.translation.width
                let i = selectionIndex
                // 끝 탭에서 더 끌면 고무줄 저항 — 들어올 페이지가 없다.
                if (i == 0 && dx > 0) || (i == tabs.count - 1 && dx < 0) { dx *= 0.28 }
                dragX = dx
            }
            .onEnded { value in
                if blocked || gate.held {
                    blocked = false
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { dragX = 0 }
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                let i = selectionIndex
                // 빠른 플릭(속도) 또는 의도적 끌기(거리+방향비) 둘 다 받는다.
                let flick = abs(value.velocity.width) > 260 && abs(dx) > 20
                let deliberate = abs(dx) > 48 && abs(dx) > abs(dy) * 1.2
                let canGo = dx < 0 ? i < tabs.count - 1 : i > 0
                guard abs(dx) > abs(dy), flick || deliberate, canGo else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { dragX = 0 }
                    return
                }
                let next = tabs[dx < 0 ? i + 1 : i - 1]
                swipeCommitted = true
                if reduceMotion {
                    selection = next
                    dragX = 0
                    return
                }
                // 선택을 곧바로 바꾸고(햅틱 즉시) dragX 를 ±폭만큼 보정해 한 프레임에 같이 적용 —
                // 인덱스 변화와 상쇄돼 시각은 연속. 그 뒤 dragX 를 0 으로 애니메이트해 안착시킨다.
                selection = next
                dragX += dx < 0 ? containerWidth : -containerWidth
                withAnimation(.snappy(duration: 0.28)) { dragX = 0 }
            }
    }
}

final class SwipePagerGate {
    var held = false
}

private struct SwipePagerGateKey: EnvironmentKey {
    static let defaultValue: SwipePagerGate? = nil
}

extension EnvironmentValues {
    var swipePagerGate: SwipePagerGate? {
        get { self[SwipePagerGateKey.self] }
        set { self[SwipePagerGateKey.self] = newValue }
    }
}

private struct HoldsSwipePager: ViewModifier {
    @Environment(\.swipePagerGate) private var gate
    @GestureState private var touching = false
    @State private var scrolling = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($touching) { _, state, _ in state = true })
            .onChange(of: touching) { _, now in gate?.held = now || scrolling }
            .onScrollPhaseChange { _, phase in
                scrolling = phase != .idle
                gate?.held = touching || scrolling
            }
    }
}

extension View {
    func holdsSwipePager() -> some View { modifier(HoldsSwipePager()) }
}
