//
//  WelcomeView.swift
//  kurl
//

import SwiftUI

/// 첫 실행 1회 — 로그인 vs 게스트를 명시적으로 가른다. 게스트를 고르면 다시 안 뜬다.
/// 읽기는 로그인 뒤에 갇히면 안 되므로(App Store 5.1.1(v)) "둘러보기"가 동등한 1급 출구다.
///
/// 구성은 "앱이 제 언어로 자기소개": 종이 본문(§1 종이 본문·액체 크롬) 위에 인앱과 똑같은
/// 초록 형광이 그어지고, 그 문장에서 초록 실이 자라 컬렉션 카드에 이어진다 — 읽다가 긋고,
/// 그은 것이 연결되는 제품의 두 동작이 그대로 첫인상. 배경·잉크·형광·유리 전부 인앱 토큰.
/// 벽(본문·카드)은 장식이라 Dynamic Type 미적용(a11y 숨김), 태그라인·버튼만 따른다.
struct WelcomeView: View {
    /// 스플래시가 걷혀 웰컴이 드러나는 순간 true — 이때 엔트런스가 시작된다.
    var revealed: Bool
    /// 스플래시 마크가 중앙에서 이 서명 자리로 글라이드해 오는 네임스페이스(matchedGeometry).
    var launchNS: Namespace.ID? = nil
    var onContinueAsGuest: () -> Void
    var onSignedIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    /// 태그라인은 브랜드 조판 — 크기 보존 + Dynamic Type 만 얹는다.
    @ScaledMetric(relativeTo: .largeTitle) private var taglineSize: CGFloat = 38
    @State private var rowsVisible = false
    /// 본문이 선 뒤 형광이 "그어지는" 박자 — 오버레이 텍스트가 이 값으로 떠오른다.
    @State private var highlightsOn = false
    /// 형광 다음 박자 — 실이 자라 컬렉션 카드에 꽂힌다.
    @State private var threadOn = false
    @State private var taglineVisible = false
    @State private var actionsVisible = false
    @State private var showLogin = false

    /// 벽 = 본문 한 단락 — 톤온톤 산문 속에서 두 구절만 형광으로 살아난다.
    /// "읽다가 긋는다"는 제품의 핵심 동작이 그대로 첫인상이 된다(레퍼런스 없는 우리 문법).
    /// 구절은 세그먼트로 나눠 로컬라이즈한다(강조 위치가 언어마다 자연스럽게 이동).
    private static let prose: [(String, Bool)] = [
        (String(localized: "글은 읽는 사람의 밑줄에서 두 번째 삶을 산다. 좋은 글은 "), false),
        (String(localized: "두 번째 읽을 때 다른 문장에 밑줄이 쳐진다."), true),
        (String(localized: " 흩어진 기록은 잊히지만, "), false),
        (String(localized: "기록은 연결될 때 길이 된다."), true),
        (String(localized: " 누군가의 문장을 내 컬렉션에 잇는 순간, 읽기는 더 이상 혼자의 일이 아니다."), false),
    ]

    var body: some View {
        ZStack {
            // 종이 — 인앱 리딩 배경 그대로(§1 종이 본문). 웰컴이 곧 첫 리딩 화면이다.
            Palette.readingBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // 서명 — 인앱 그대로의 그린 마크 + 잉크 워드마크.
                HStack(spacing: 10) {
                    KurlMark(drawn: [true, true, true])
                        .frame(width: 44, height: 27)
                        .launchMatched("launchMark", in: launchNS, isSource: revealed)
                    Text(verbatim: "kurl")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-1.0)
                        .foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, Metrics.gutter + 4)
                .opacity(rowsVisible ? 1 : 0)
                .offset(y: rowsVisible ? 0 : 6)

                Spacer(minLength: 16)

                proseWall

                connectionChip
                    .padding(.horizontal, Metrics.gutter + 4)

                // 태그라인 — 종이 위 잉크 헤비(인앱 제목의 목소리).
                Text("읽고, 쓰고,\n연결하다.")
                    .font(.system(size: taglineSize, weight: .heavy))
                    .tracking(-0.6)
                    .lineSpacing(3)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Metrics.gutter + 4)
                    .padding(.top, 28)
                    .opacity(taglineVisible ? 1 : 0)
                    .offset(y: taglineVisible ? 0 : 14)
                    .blur(radius: taglineVisible ? 0 : 3)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 16)

                // 두 알약 — 시작하기=브랜드 그린 솔리드(인앱 주행동), 둘러보기=유리(액체 크롬).
                // 게스트 출구가 시작하기와 같은 줄, 같은 키(App Store 5.1.1(v) 1급 출구).
                HStack(spacing: 10) {
                    Button {
                        onContinueAsGuest()
                    } label: {
                        Text("로그인 없이 둘러보기")
                            .font(.system(size: 15 * unit, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: .capsule)
                    .overlay(Capsule().strokeBorder(Palette.hairlineStrong.opacity(0.6), lineWidth: 1))

                    Button {
                        showLogin = true
                    } label: {
                        Text("시작하기")
                            .font(.system(size: 16 * unit, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Palette.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Metrics.gutter + 4)
                .padding(.bottom, 24)
                .opacity(actionsVisible ? 1 : 0)
                .offset(y: actionsVisible ? 0 : 16)
            }
            .padding(.top, 24)
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet(message: "계정 하나면 읽고, 쓰고, 연결한 것이 어디서든 이어져요.") {
                onSignedIn()
            }
        }
        .onAppear { if revealed { play() } }
        .onChange(of: revealed) { _, now in if now { play() } }
    }

    // MARK: 연결 실 + 컬렉션 카드 — 그은 문장이 어딘가에 이어진다(연결 그래프의 최소 표현)

    private var connectionChip: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 실 — 두 번째 형광("길이 된다") 아래께에서 시작점(점)을 찍고 자라 내려온다.
            VStack(spacing: 0) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.accent)
                    .frame(width: 2, height: 24)
            }
            .padding(.leading, 96)
            .scaleEffect(y: threadOn ? 1 : 0.01, anchor: .top)
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text("'다시 읽고 싶은'에 이어짐")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Image(systemName: "square.stack")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Palette.cardBg)
                    .shadow(color: .black.opacity(0.07), radius: 12, y: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(0.3), lineWidth: 1))
            .padding(.leading, 44)
            .opacity(threadOn ? 1 : 0)
            .offset(y: threadOn ? 0 : -8)
        }
        // 데모 소품 — 보이스오버는 태그라인으로 직행.
        .accessibilityHidden(true)
    }

    // MARK: 하이라이트 벽 — 본문에 형광이 그어진다

    /// 본문(잉크)과 형광 오버레이(같은 문자열·같은 조판이라 글리프가 정확히 겹친다) —
    /// 오버레이만 나중에 떠올라 "형광펜이 그어지는" 순간이 엔트런스가 된다.
    private var proseWall: some View {
        ZStack(alignment: .topLeading) {
            Text(Self.attributed(highlighted: false))
            Text(Self.attributed(highlighted: true))
                .opacity(highlightsOn ? 1 : 0)
        }
        .lineSpacing(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter + 4)
        .opacity(rowsVisible ? 1 : 0)
        .offset(y: rowsVisible ? 0 : 14)
        .blur(radius: rowsVisible ? 0 : 3)
        // 벽은 장식 — 보이스오버는 태그라인부터 읽는다.
        .accessibilityHidden(true)
    }

    /// highlighted=false 는 전체 잉크 본문. true 는 형광 구절만 보이는 오버레이(나머지는 투명) —
    /// 두 장을 겹쳐 오버레이 불투명도만 올리면 같은 자리에서 형광이 켜진다(인앱 하이라이트 결).
    private static func attributed(highlighted: Bool) -> AttributedString {
        var out = AttributedString()
        for (text, isHighlight) in prose {
            var run = AttributedString(text)
            run.font = .system(size: 21, weight: .regular)
            run.tracking = -0.1
            if !highlighted {
                run.foregroundColor = Palette.ink
            } else if isHighlight {
                run.foregroundColor = Palette.ink
                run.backgroundColor = Palette.accent.opacity(0.19)
                run.underlineStyle = .single
                run.underlineColor = UIColor(Palette.accent)
            } else {
                run.foregroundColor = .clear
            }
            out += run
        }
        return out
    }

    // MARK: 엔트런스 — 벽이 줄줄이 서고, 태그라인·버튼이 한 박자씩 따라온다

    private func play() {
        guard !reduceMotion else {
            rowsVisible = true
            highlightsOn = true
            threadOn = true
            taglineVisible = true
            actionsVisible = true
            return
        }
        // 실크 — 빠르게 나와 아주 길게 눕는 커브. 팝 없이 전 박자가 같은 결로 떠오른다.
        let silk = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)
        withAnimation(silk) { rowsVisible = true }
        // 본문이 자리잡은 뒤 형광이 그어지고, 그은 문장에서 실이 자라 컬렉션에 꽂힌다 —
        // 읽다가 긋고, 그은 것이 이어지는 제품의 서사가 엔트런스 그 자체.
        withAnimation(silk.delay(0.55)) { highlightsOn = true }
        withAnimation(.smooth(duration: 0.7).delay(1.05)) { threadOn = true }
        withAnimation(silk.delay(1.3)) { taglineVisible = true }
        withAnimation(silk.delay(1.45)) { actionsVisible = true }
    }
}
