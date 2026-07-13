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
    /// 웰컴으로 마크를 이어 보낼 네임스페이스(matchedGeometry) — 없으면(프리뷰) 그냥 정적.
    var launchNS: Namespace.ID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barsDrawn = [false, false, false]
    @State private var wordVisible = false
    /// 마지막 박자 — 워드마크 뒤로 형광이 좌→우로 그어진다(웰컴·인앱 하이라이트와 같은 결).
    @State private var swept = false
    /// 워드마크는 사다리 밖 브랜드 자산(고유 자간) — 크기 보존 + Dynamic Type 만 얹는다.
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 28

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                KurlMark(drawn: barsDrawn)
                    .frame(width: 84, height: 51)
                    .launchMatched("launchMark", in: launchNS)
                Text(verbatim: "kurl")
                    .font(.system(size: wordmarkSize, weight: .bold))
                    .tracking(-1.1)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.accent.opacity(0.19))
                            .scaleEffect(x: swept ? 1 : 0.001, anchor: .leading)
                    }
                    .overlay(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.accent)
                            .frame(height: 2)
                            .offset(y: 4)
                            .scaleEffect(x: swept ? 1 : 0.001, anchor: .leading)
                    }
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
            swept = true
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
        // 이름 위에 형광 한 획 — 읽다가 긋는 제품의 손짓을 스플래시가 먼저 해 보인다.
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.5).delay(0.85)) {
            swept = true
        }
    }
}

extension View {
    /// matchedGeometryEffect 를 네임스페이스가 있을 때만 적용 — 프리뷰(ns=nil)에서도 산다.
    /// 스플래시→웰컴 마크 핸드오프 한 군데에서만 쓴다.
    @ViewBuilder
    func launchMatched(_ id: String, in ns: Namespace.ID?, isSource: Bool = true) -> some View {
        if let ns {
            matchedGeometryEffect(id: id, in: ns, isSource: isSource)
        } else {
            self
        }
    }
}

/// 3-bar 브랜드 마크 — 웹 SVG(viewBox 28×17)의 rect 좌표를 그대로 스케일.
/// tint 로 색을 바꾼다(기본 브랜드 그린, 그린 면 위에선 흰색 등).
struct KurlMark: View {
    let drawn: [Bool]
    var tint: Color = Palette.accent

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
                        .fill(tint)
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
                WaveShape(phase: reduceMotion ? 0 : t * 0.55, amplitude: 7, wavelength: 260)
                    .fill(Palette.accent.opacity(0.08))
                WaveShape(phase: reduceMotion ? 1.8 : t * 0.85 + 1.8, amplitude: 5, wavelength: 185)
                    .fill(Palette.accent.opacity(0.11))
            }
            .frame(height: 92)
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
