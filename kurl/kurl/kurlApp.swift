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
            ZStack {
                // 스플래시가 걷힐 때 본 화면이 1.5% 에서 제자리로 — 막이 오르는 한 호흡.
                RootView()
                    .scaleEffect(showSplash && !reduceMotion ? 1.015 : 1)
                    .animation(.easeOut(duration: 0.5), value: showSplash)
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
                        .transition(.opacity)
                }
            }
            .task {
                MockSelfTest.runIfRequested()
                // 첫 실행 1회, 비로그인일 때만 웰컴. 게스트를 고르면 플래그가 서고 다시 안 뜬다.
                // (`--screen welcome` 은 simctl 터치 불가 우회 — 스크린샷 검증 진입로.)
                let forceWelcome = Config.launchValue(after: "--screen") == "welcome"
                showWelcome = forceWelcome || (!hasCompletedWelcome && !AuthStore.shared.isSignedIn)
                // 마크 드로잉(~0.4s)+워드마크(~0.8s)가 끝나고 한 박자 머문 뒤 걷는다.
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.6))
                // 막이 걷히며 마크가 스플래시 자리에서 웰컴 자리로 글라이드한다(matched). 같은
                // 트랜잭션에서 reveal 을 켜 마크 핸드오프와 텍스트 스태거가 한 호흡으로 이어진다.
                withAnimation(.easeOut(duration: reduceMotion ? 0.35 : 0.5)) {
                    showSplash = false
                    welcomeRevealed = true
                }
            }
        }
    }

    private func dismissWelcome() {
        hasCompletedWelcome = true
        withAnimation(.easeOut(duration: 0.3)) { showWelcome = false }
    }
}
