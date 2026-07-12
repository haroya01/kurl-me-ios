//
//  TabBarVisibility.swift
//  kurl
//

import SwiftUI

/// 하단 탭바 숨김/복귀의 단일 손잡이 — 스레드식 동작을 우리가 직접 태운다.
///
/// iOS 26/27.0 런타임은 `.tabBarMinimizeBehavior(.onScrollDown)` 를 시뮬·실기기 모두
/// 안 태운다(2026-06-13 실기기 확정, 우리 구조 무관). OS 가 죽어 있는 동안 스크롤로 바가
/// 사라지지 않아, 스레드처럼 스크롤 방향을 직접 관측해 시스템 유리 탭바를 숨겼다 되살린다
/// (AGENTS §1: 시스템 유리 탭바 유지 — 커스텀 바로 갈아치우지 않는다).
///
/// 방향 판정은 각 탭 루트의 스크롤 표면이 `.tracksTabBarVisibility()` 로 오프셋을 보내면
/// 여기서 누적한다. 아래로 읽어 내려가면(내용이 위로) 숨기고, 위로 되돌리면 되살린다.
@MainActor
@Observable
final class TabBarVisibility {
    /// 시스템 탭바를 숨겨야 하는가 — RootView 가 `.toolbar(.hidden, for: .tabBar)` 로 태운다.
    private(set) var hidden = false

    /// 마지막으로 방향을 확정한 기준 오프셋. 여기서 임계 이상 벗어나면 방향을 뒤집는다.
    private var anchorOffset: CGFloat = 0
    /// 직전 프레임 오프셋 — 방향(부호)만 뽑는 데 쓴다.
    private var lastOffset: CGFloat = 0

    /// 방향을 확정하는 최소 이동량(pt) — 플릭 관성의 미세 떨림으로 바가 깜빡이지 않게.
    private let threshold: CGFloat = 44
    /// 상단 근처에선 늘 보인다 — 리스트 맨 위에서 바가 사라져 있으면 길을 잃는다.
    private let alwaysVisibleTop: CGFloat = 8

    /// 스크롤 표면이 매 프레임 넘기는 세로 오프셋(safe-area 보정 포함). 방향이 임계를 넘으면
    /// 숨김 상태를 바꾼다. 애니메이션은 호출부(모디파이어)가 reduce-motion 을 봐서 감싼다.
    func report(offset: CGFloat) {
        defer { lastOffset = offset }

        // 상단 근처 = 항상 보임(맨 위에서 숨은 채 시작하지 않게).
        if offset <= alwaysVisibleTop {
            anchorOffset = offset
            setHidden(false)
            return
        }

        let goingDown = offset > lastOffset  // 내용이 위로 = 아래로 읽는 중
        // 방향이 바뀌면 기준점을 지금으로 다시 잡는다 — 되돌리는 즉시 임계를 새로 센다.
        if (goingDown && offset < anchorOffset) || (!goingDown && offset > anchorOffset) {
            anchorOffset = offset
        }

        let moved = offset - anchorOffset
        if moved > threshold {
            anchorOffset = offset
            setHidden(true)   // 충분히 내렸다 → 숨김
        } else if moved < -threshold {
            anchorOffset = offset
            setHidden(false)  // 충분히 올렸다 → 복귀
        }
    }

    /// 탭 전환·화면 진입 시 항상 보이는 상태로 되돌린다(새 탭이 숨은 바로 시작하지 않게).
    func reset() {
        anchorOffset = 0
        lastOffset = 0
        setHidden(false)
    }

    private func setHidden(_ value: Bool) {
        if hidden != value { hidden = value }
    }
}

private struct TabBarVisibilityKey: EnvironmentKey {
    static let defaultValue: TabBarVisibility? = nil
}

extension EnvironmentValues {
    /// 탭 루트의 스크롤 표면이 방향을 보고할 공유 손잡이(없으면 추적 안 함 — 상세·시트 등).
    var tabBarVisibility: TabBarVisibility? {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

/// 탭 루트의 스크롤 표면에 붙여 세로 오프셋을 공유 상태로 흘려보낸다 — 스레드식 숨김의 눈.
/// 상세/시트 등 탭 밖 스크롤엔 붙이지 않는다(그쪽은 탭바가 이미 없다).
private struct TracksTabBarVisibility: ViewModifier {
    let enabled: Bool
    @Environment(\.tabBarVisibility) private var visibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            guard enabled, let visibility else { return }
            // 숨김↔복귀 전환만 부드럽게 — reduce-motion 이면 즉시 토글(움직임 없이 존재만).
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                visibility.report(offset: offset)
            }
        }
    }
}

extension View {
    /// 이 스크롤 표면의 방향을 공유 `TabBarVisibility` 로 보낸다(탭 루트 전용).
    /// `enabled` 로 활성 페이지만 몰게 한다(ZStack 에 여러 페이지가 상주하는 피드).
    func tracksTabBarVisibility(_ enabled: Bool = true) -> some View {
        modifier(TracksTabBarVisibility(enabled: enabled))
    }
}
