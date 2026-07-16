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
    /// 커스텀 바가 실제로 숨겨야 하는가 — 스크롤 숨김(scrollHidden)이거나 강제 숨김(forceHidden)이면
    /// 숨는다. RootView 의 FloatingTabBar 가 이 값을 읽는다. 두 원천 모두 저장 프로퍼티라
    /// @Observable 이 확실히 추적한다(집합의 isEmpty 를 computed 로 읽으면 갱신이 새는 함정이 있었다).
    var hidden: Bool { scrollHidden || forceHidden }

    /// 스크롤 방향으로 확정한 숨김 — 내리면 true, 올리면 false(스레드식).
    private(set) var scrollHidden = false

    /// 강제 숨김 상태 — 저장 프로퍼티라 @Observable 이 확실히 추적한다. forceHiders 가 바뀔 때마다 다시 계산한다.
    private(set) var forceHidden = false

    /// 바를 통째로 접어 달라는 화면들의 토큰 집합 — 설정처럼 iOS 관습상 탭바가 없어야 하는
    /// 푸시 스택에서 `.hidesTabBar()` 인스턴스마다 제 토큰을 넣고(등장) 뺀다(퇴장). 집합이라
    /// 넣고 빼는 순서가 뒤엉키거나 중복돼도(SwiftUI 는 NavigationStack 전환 때 onAppear·
    /// onDisappear 순서를 보장하지 않는다) 결과가 흐트러지지 않는다 — 카운트가 어긋나 바가
    /// 영영 안 돌아오던 함정을 피한다. 설정 안 하위 푸시가 겹쳐도(설정→차단 목록 등) 마지막
    /// 화면이 빠질 때만 집합이 비어 바가 돌아온다.
    private var forceHiders: Set<UUID> = [] {
        didSet { forceHidden = !forceHiders.isEmpty }
    }

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

    /// 탭 전환·화면 진입 시 스크롤 숨김만 풀어 준다(새 탭이 숨은 바로 시작하지 않게).
    /// 강제 숨김(설정 스택)은 화면이 살아 있는 한 유지돼야 하므로 여기서 건드리지 않는다.
    func reset() {
        anchorOffset = 0
        lastOffset = 0
        setHidden(false)
    }

    /// `.hidesTabBar()` 화면이 떠 바를 통째로 접는다 — 제 토큰을 집합에 넣는다(중복 무해).
    func addHider(_ token: UUID) { forceHiders.insert(token) }

    /// `.hidesTabBar()` 화면이 사라져 접힘 요청을 거둔다 — 제 토큰만 뺀다(없어도 무해).
    /// 집합이 비면 바가 돌아온다.
    func removeHider(_ token: UUID) { forceHiders.remove(token) }

    private func setHidden(_ value: Bool) {
        if scrollHidden != value { scrollHidden = value }
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

/// 스크롤 표면에 붙여 세로 오프셋을 공유 상태로 흘려보낸다 — 스레드식 숨김의 눈.
/// 커스텀 바는 푸시 화면 위에도 떠 있으므로 탭 루트만이 아니라 글 상세처럼 오래 읽는
/// 푸시 표면도 붙인다 — 붙인 표면만 보고하는 옵트인이라, 안 붙인 화면은 상태를 안 건드린다.
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
    /// 이 스크롤 표면의 방향을 공유 `TabBarVisibility` 로 보낸다.
    /// `enabled` 로 활성 표면만 몰게 한다(ZStack 상주 피드 페이지·덱에 임베드된 상세).
    func tracksTabBarVisibility(_ enabled: Bool = true) -> some View {
        modifier(TracksTabBarVisibility(enabled: enabled))
    }

    /// 이 화면이 떠 있는 동안 커스텀 하단바를 통째로 접는다 — 설정처럼 iOS 관습상 탭바가
    /// 없어야 하는 푸시 스택에서 쓴다(하단 행이 바에 가려 도달 못 하던 자리). 등장/퇴장으로
    /// 제 토큰을 집합에 넣고 빼, 하위 푸시가 겹쳐도 스택을 완전히 벗어날 때만 바가 돌아온다.
    func hidesTabBar() -> some View {
        modifier(HidesTabBar())
    }
}

/// 화면 생명주기에 맞춰 공유 `TabBarVisibility` 의 강제 숨김 집합에 제 토큰을 넣고 뺀다.
/// 스크롤 방향과 무관하게 바를 접으므로, 스크롤 없는 설정류 화면도 바가 확실히 비켜선다.
///
/// 토큰은 인스턴스마다 하나로 고정한다 — onAppear 가 여러 번 불려도(하위 푸시에서 되돌아옴)
/// 같은 토큰을 다시 넣을 뿐이라 무해하고, onDisappear 는 제 토큰만 뺀다. 집합이라 넣고 빼는
/// 순서가 뒤엉켜도 결과가 안정적이다(카운트식은 순서가 어긋나면 바가 영영 안 돌아왔다).
private struct HidesTabBar: ViewModifier {
    @Environment(\.tabBarVisibility) private var visibility
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { visibility?.addHider(token) }
            .onDisappear { visibility?.removeHider(token) }
    }
}
