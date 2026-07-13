//
//  WelcomeView.swift
//  kurl
//

import SwiftUI

/// 첫 실행 1회 — 로그인 vs 게스트를 명시적으로 가른다. 게스트를 고르면 다시 안 뜬다.
/// 읽기는 로그인 뒤에 갇히면 안 되므로(App Store 5.1.1(v)) "둘러보기"가 동등한 1급 출구다.
///
/// 구성은 "단어 벽": 브랜드 그린 들판 위에 우리 우주의 단어들(하이라이트·시리즈·길·연결…)이
/// 두 톤으로 깔리고, 검정 태그라인 한 줄이 그 위에 선다 — 일러스트 없이 어휘가 곧 첫인상.
/// 벽은 장식이라 Dynamic Type 을 따르지 않고(a11y 트리에서도 숨김), 태그라인·버튼만 따른다.
/// 다크에서도 들판은 같은 그린 — 첫 화면은 모드가 아니라 브랜드가 정한다.
struct WelcomeView: View {
    /// 스플래시가 걷혀 웰컴이 드러나는 순간 true — 이때 엔트런스가 시작된다.
    var revealed: Bool
    /// 스플래시 마크 글라이드용(이전 구성) — 들판이 그린이라 마크는 스플래시와 함께 걷힌다.
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
            // 들판 — 브랜드 그린 풀블리드. 라이트/다크 공통(첫 화면은 브랜드가 정한다).
            Palette.accent.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // 서명 — 흰 마크 + 워드마크. 스플래시 마크는 막과 함께 걷히고 여기 흰 서명이 남는다.
                HStack(spacing: 10) {
                    KurlMark(drawn: [true, true, true], tint: .white)
                        .frame(width: 44, height: 27)
                    Text(verbatim: "kurl")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-1.0)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Metrics.gutter + 4)
                .opacity(rowsVisible ? 1 : 0)

                Spacer(minLength: 18)

                proseWall

                // 태그라인 — 들판 위 검정 한 방(다크에서도 검정: 그린 위 대비가 곧 목소리).
                Text("읽고, 쓰고,\n연결하다.")
                    .font(.system(size: taglineSize, weight: .heavy))
                    .tracking(-0.6)
                    .lineSpacing(3)
                    .foregroundStyle(.black)
                    .padding(.horizontal, Metrics.gutter + 4)
                    .padding(.top, 26)
                    .opacity(taglineVisible ? 1 : 0)
                    .offset(y: taglineVisible ? 0 : 10)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 18)

                // 트위치식 두 알약 — 게스트 출구가 시작하기와 같은 줄, 같은 키(5.1.1(v) 1급 출구).
                HStack(spacing: 10) {
                    Button {
                        onContinueAsGuest()
                    } label: {
                        Text("로그인 없이 둘러보기")
                            .font(.system(size: 15 * unit, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showLogin = true
                    } label: {
                        Text("시작하기")
                            .font(.system(size: 16 * unit, weight: .bold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Metrics.gutter + 4)
                .padding(.bottom, 24)
                .opacity(actionsVisible ? 1 : 0)
                .offset(y: actionsVisible ? 0 : 12)
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

    // MARK: 단어 벽 — 우리 우주의 어휘가 곧 배경

    /// 본문(톤온톤)과 형광 오버레이(같은 문자열·같은 조판이라 글리프가 정확히 겹친다) —
    /// 오버레이만 나중에 떠올라 "형광펜이 그어지는" 순간이 엔트런스가 된다.
    private var proseWall: some View {
        ZStack(alignment: .topLeading) {
            Text(Self.attributed(highlighted: false))
            Text(Self.attributed(highlighted: true))
                .opacity(highlightsOn ? 1 : 0)
        }
        .lineSpacing(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter + 4)
        .opacity(rowsVisible ? 1 : 0)
        .offset(y: rowsVisible ? 0 : 8)
        // 벽은 장식 — 보이스오버는 태그라인부터 읽는다.
        .accessibilityHidden(true)
    }

    /// highlighted=false 는 전체 톤온톤 본문. true 는 형광 구절만 보이는 오버레이(나머지는 투명) —
    /// 두 장을 겹쳐 오버레이 불투명도만 올리면 같은 자리에서 형광이 켜진다.
    private static func attributed(highlighted: Bool) -> AttributedString {
        var out = AttributedString()
        for (text, isHighlight) in prose {
            var run = AttributedString(text)
            run.font = .system(size: 23, weight: .semibold)
            if !highlighted {
                run.foregroundColor = .white.opacity(0.34)
            } else if isHighlight {
                run.foregroundColor = .white
                run.backgroundColor = .white.opacity(0.16)
                run.underlineStyle = .single
                run.underlineColor = UIColor.white.withAlphaComponent(0.85)
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
            taglineVisible = true
            actionsVisible = true
            return
        }
        rowsVisible = true
        // 본문이 자리잡은 뒤 형광이 그어진다 — 이 한 박자가 화면의 서사(읽다가 긋는다).
        withAnimation(.easeOut(duration: 0.5).delay(0.55)) { highlightsOn = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.85)) { taglineVisible = true }
        withAnimation(.easeOut(duration: 0.45).delay(1.0)) { actionsVisible = true }
    }
}
