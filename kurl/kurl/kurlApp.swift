//
//  kurlApp.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

@main
struct kurlApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @State private var showSplash = true
    @State private var showWelcome = false
    /// 스플래시가 걷히는 순간 true — 웰컴 엔트런스가 이때 시작된다(t0 가 아니라).
    @State private var welcomeRevealed = false
    /// 스플래시 → 웰컴 마크 핸드오프용 — 마크가 스플래시 자리에서 웰컴 자리로 이어진다.
    @Namespace private var launchNS

    var body: some Scene {
        WindowGroup {
            // 격리 WYSIWYG 에디터 하네스 진입로(스크린샷 검증 전용) — 다른 UI 를 전혀 안 태운다.
            if Config.launchValue(after: "--screen") == "editor2" {
                EditorHarnessRoot()
            } else {
            ZStack {
                // 스플래시가 걷힐 때 본 화면이 1.5% 에서 제자리로 — 막이 오르는 한 호흡(실크).
                RootView()
                    .scaleEffect(showSplash && !reduceMotion ? 1.015 : 1)
                    .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.6), value: showSplash)
                // 첫 실행 1회 웰컴 — 스플래시 뒤에 깔려 있다가 막이 걷히면 드러난다.
                if showWelcome {
                    WelcomeView(
                        revealed: welcomeRevealed,
                        launchNS: launchNS,
                        onContinueAsGuest: { dismissWelcome() },
                        onSignedIn: { dismissWelcome() })
                        .zIndex(1)
                        .transition(.opacity)
                }
                if showSplash {
                    SplashView(launchNS: launchNS)
                        .zIndex(2)
                        // 걷힐 때 마크·워드마크가 위로 떠오르며 사라진다 — 매일 보는 로그인
                        // 커튼의 마무리 한 획(웰컴 경로에선 마크 글라이드와 자연히 겹친다).
                        .transition(.opacity.combined(with: .offset(y: -12)))
                }
            }
            .task {
                MockSelfTest.runIfRequested()
                // 첫 실행 1회, 비로그인일 때만 웰컴. 게스트를 고르면 플래그가 서고 다시 안 뜬다.
                // (`--screen welcome` 은 simctl 터치 불가 우회 — 스크린샷 검증 진입로.)
                let forceWelcome = Config.launchValue(after: "--screen") == "welcome"
                // 검증용 딥링크(--post 등)는 목적지가 명확하니 웰컴 막을 띄우지 않는다 —
                // 안 그러면 웰컴이 목적 화면을 덮어 터치를 삼킨다.
                showWelcome = forceWelcome
                    || (!hasCompletedWelcome && !AuthStore.shared.isSignedIn && !Config.hasDeepLinkEntry)
                // 마크 드로잉(~0.4s)→워드마크(~0.8s)→형광 한 획(~1.05s)이 끝난 뒤 걷는다.
                // 웰컴(첫 실행)은 한 박자 더 머물고, 매일 보는 로그인 커튼은 가볍게 1.15s.
                let hold: Double = reduceMotion ? 0.6 : (showWelcome ? 1.6 : 1.15)
                try? await Task.sleep(for: .seconds(hold))
                // 막이 걷히며 마크가 스플래시 자리에서 웰컴 자리로 글라이드한다(matched). 같은
                // 트랜잭션에서 reveal 을 켜 마크 핸드오프와 텍스트 스태거가 한 호흡으로 이어진다.
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: reduceMotion ? 0.35 : 0.6)) {
                    showSplash = false
                    welcomeRevealed = true
                }
            }
            // 로그아웃하면 로그인 화면(웰컴)으로 — 페이드로 올라오고 마크 엔트런스가 다시 재생된다.
            .onChange(of: AuthStore.shared.isSignedIn) { wasSignedIn, signedIn in
                if wasSignedIn && !signedIn {
                    welcomeRevealed = true
                    withAnimation(.easeOut(duration: 0.4)) { showWelcome = true }
                }
            }
            }
        }
    }

    private func dismissWelcome() {
        hasCompletedWelcome = true
        withAnimation(.easeOut(duration: 0.3)) { showWelcome = false }
    }
}
