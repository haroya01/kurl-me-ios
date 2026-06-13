//
//  SplashView.swift
//  kurl
//

import SwiftUI

/// 앱 기동 스플래시 — 웹 제품 전환 warp 연출의 이식판: 3-bar 마크가 줄별로
/// 왼쪽에서 그려지고(0 / 0.08 / 0.16s 스태거, 0.24s, cubic-bezier(0.22,1,0.36,1)),
/// 0.46s 에 워드마크가 7px 아래에서 떠오른다. 하단엔 브랜드 그린 물결 두 겹이 천천히 흐른다.
/// reduce-motion 이면 전부 정지 상태로 그려지고 빨리 사라진다.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barsDrawn = [false, false, false]
    @State private var wordVisible = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                KurlMark(drawn: barsDrawn)
                    .frame(width: 84, height: 51)
                Text(verbatim: "kurl")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-1.1)
                    .foregroundStyle(Palette.ink)
                    .opacity(wordVisible ? 1 : 0)
                    .offset(y: wordVisible ? 0 : 7)
            }

            WaveBand()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .onAppear { play() }
    }

    private func play() {
        guard !reduceMotion else {
            barsDrawn = [true, true, true]
            wordVisible = true
            return
        }
        // 웹 warp 의 타이밍 그대로 — 줄별 스태거 후 워드마크.
        for i in 0..<3 {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24).delay(Double(i) * 0.08)) {
                barsDrawn[i] = true
            }
        }
        withAnimation(.easeOut(duration: 0.34).delay(0.46)) {
            wordVisible = true
        }
    }
}

/// 3-bar 브랜드 마크 — 웹 SVG(viewBox 28×17)의 rect 좌표를 그대로 스케일.
struct KurlMark: View {
    let drawn: [Bool]

    // (x, y, width) — height 3.4, rx 1.7 고정. viewBox 기준.
    private static let bars: [(CGFloat, CGFloat, CGFloat)] = [
        (6, 1, 20),
        (0, 7.3, 28),
        (9, 13.6, 17),
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 28
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { i in
                    let bar = Self.bars[i]
                    RoundedRectangle(cornerRadius: 1.7 * scale)
                        .fill(Palette.accent)
                        .frame(width: bar.2 * scale, height: 3.4 * scale)
                        .scaleEffect(x: drawn[i] ? 1 : 0, anchor: .leading)
                        .offset(x: bar.0 * scale, y: bar.1 * scale)
                }
            }
        }
    }
}

/// 하단 물결 — 두 겹의 사인파가 서로 다른 속도로 흐른다. 브랜드 그린, 아주 옅게.
private struct WaveBand: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                WaveShape(phase: reduceMotion ? 0 : t * 0.7, amplitude: 9, wavelength: 240)
                    .fill(Palette.accent.opacity(0.10))
                WaveShape(phase: reduceMotion ? 1.8 : t * 1.1 + 1.8, amplitude: 6, wavelength: 170)
                    .fill(Palette.accent.opacity(0.14))
            }
            .frame(height: 110)
        }
        .allowsHitTesting(false)
    }
}

private struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat
    var wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let crest = rect.minY + amplitude
        path.move(to: CGPoint(x: rect.minX, y: crest + sin(phase) * amplitude))
        var x = rect.minX
        while x <= rect.maxX {
            let relative = Double((x - rect.minX) / wavelength) * 2 * .pi
            let y = crest + sin(relative + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 4
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    SplashView()
}
