//
//  WelcomeView.swift
//  kurl
//

import SwiftUI

/// 첫 실행 1회 — 로그인 vs 게스트를 명시적으로 가른다. 게스트를 고르면 다시 안 뜬다.
/// 읽기는 로그인 뒤에 갇히면 안 되므로(App Store 5.1.1(v)) "둘러보기"가 동등한 1급 출구다.
/// 로그인 버튼 묶음은 계정 탭·글쓰기 게이트·로그인 시트와 같은 공유 컴포넌트.
///
/// 배경은 브랜드 그린 메시 그라데이션이 아주 느리게 숨쉰다(조용함 안에서 살아 있는 결, §10).
/// 그 위에 마크·워드마크가 크게 서고, 로그인 묶음은 유리 패널로 떠 있다(메시가 유리 뒤로 굴절).
/// 엔트런스는 스플래시의 결을 잇는다 — 마크가 줄별로 그려지고 워드마크·태그라인·버튼이
/// 한 박자씩 떠오른다. 웰컴은 스플래시 *뒤에* 깔려 있으므로 모션은 `revealed`(막이 걷힘)에서
/// 시작해야 사용자가 본다 — onAppear(=앱 기동 t0)가 아니라.
struct WelcomeView: View {
    /// 스플래시가 걷혀 웰컴이 드러나는 순간 true — 이때 엔트런스가 시작된다.
    var revealed: Bool
    var onContinueAsGuest: () -> Void
    var onSignedIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var barsDrawn = [false, false, false]
    @State private var wordVisible = false
    @State private var taglineVisible = false
    @State private var actionsVisible = false

    var body: some View {
        ZStack {
            livingMesh

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                KurlMark(drawn: barsDrawn)
                    .frame(width: 104, height: 63)
                Text(verbatim: "kurl")
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-1.4)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 18)
                    .opacity(wordVisible ? 1 : 0)
                    .offset(y: wordVisible ? 0 : 9)
                Text("읽고, 쓰고, 모으는 곳.")
                    .font(.system(size: 16 * unit))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 10)
                    .opacity(taglineVisible ? 1 : 0)
                    .offset(y: taglineVisible ? 0 : 9)

                Spacer(minLength: 0)

                // 로그인 묶음은 유리 패널로 — 메시가 유리 뒤로 굴절해 "떠 있는" 느낌.
                // 패널만 유리, 그 안의 주행동(Google)은 솔리드 — 유리 위 유리 금지(§1.4).
                VStack(spacing: 10) {
                    AuthProviderButtons { onSignedIn() }
                    Button {
                        onContinueAsGuest()
                    } label: {
                        Text("로그인 없이 둘러보기")
                            .font(.system(size: 15 * unit, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
                .opacity(actionsVisible ? 1 : 0)
                .offset(y: actionsVisible ? 0 : 14)
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter + 4)
            .padding(.top, 72)
            .padding(.bottom, 28)
        }
        .onAppear { if revealed { play() } }
        .onChange(of: revealed) { _, now in if now { play() } }
    }

    // MARK: 배경 — 숨쉬는 브랜드 그린 메시

    private var livingMesh: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                MeshGradient(width: 3, height: 3, points: meshPoints(t), colors: meshColors)
            }
        }
        .ignoresSafeArea()
    }

    /// 가운데 점을 아주 느린 사인으로 흔든다 — 글로우가 숨쉬듯 움직인다(반경 작게).
    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        let dx = reduceMotion ? 0 : Float(sin(t * 0.22)) * 0.11
        let dy = reduceMotion ? 0 : Float(cos(t * 0.17)) * 0.09
        return [
            .init(0, 0), .init(0.5, 0), .init(1, 0),
            .init(0, 0.5), .init(0.5 + dx, 0.55 + dy), .init(1, 0.5),
            .init(0, 1), .init(0.5, 1), .init(1, 1),
        ]
    }

    /// 위는 종이(거의 투명), 아래로 갈수록 브랜드 그린 글로우 — 조용하게.
    private var meshColors: [Color] {
        let g = Palette.accent
        return [
            g.opacity(0.06), .clear, g.opacity(0.06),
            g.opacity(0.12), g.opacity(0.18), g.opacity(0.12),
            g.opacity(0.24), g.opacity(0.34), g.opacity(0.24),
        ]
    }

    // MARK: 엔트런스 — 스플래시 warp 타이밍 그대로(줄별 스태거 → 워드마크 → 태그라인 → 버튼)

    private func play() {
        guard !reduceMotion else {
            barsDrawn = [true, true, true]
            wordVisible = true
            taglineVisible = true
            actionsVisible = true
            return
        }
        for i in 0..<3 {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.34).delay(0.08 + Double(i) * 0.1)) {
                barsDrawn[i] = true
            }
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.48)) { wordVisible = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) { taglineVisible = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.78)) { actionsVisible = true }
    }
}
