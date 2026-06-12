//
//  kurlApp.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

@main
struct kurlApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 스플래시가 걷힐 때 본 화면이 1.5% 에서 제자리로 — 막이 오르는 한 호흡.
                RootView()
                    .scaleEffect(showSplash && !reduceMotion ? 1.015 : 1)
                    .animation(.easeOut(duration: 0.5), value: showSplash)
                if showSplash {
                    SplashView()
                        .zIndex(1)
                        .transition(.opacity)
                }
            }
            .task {
                MockSelfTest.runIfRequested()
                // 마크 드로잉(~0.4s)+워드마크(~0.8s)가 끝나고 한 박자 머문 뒤 걷는다.
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.6))
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
        }
    }
}
