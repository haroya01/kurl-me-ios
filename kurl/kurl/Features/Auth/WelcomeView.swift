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
    @State private var taglineVisible = false
    @State private var actionsVisible = false
    @State private var showLogin = false

    /// 벽 한 줄 — (단어, 강조) 나열. 강조는 흰색 볼드, 나머지는 반투명 흰색(톤온톤).
    /// 행마다 왼쪽으로 다르게 블리드해 "화면보다 큰 세계"로 읽힌다. 조합은 고정(결정적).
    /// 강조 단어는 늘 온전히 보이고(잘리면 정체를 잃는다) 필러만 좌우로 잘려 나간다 —
    /// 행마다 필러를 뒤에 더 붙여 오른쪽 끝까지 흘러넘치게(화면보다 큰 세계).
    private static let wall: [(offset: CGFloat, words: [(LocalizedStringKey, Bool)])] = [
        (-40, [("독서", false), ("하이라이트", true), ("기록", false), ("에세이", false)]),
        (-64, [("사진", false), ("회고", true), ("개발", false), ("디자인", false)]),
        (-84, [("일상", false), ("태그", false), ("시리즈", true), ("여행", false), ("밑줄", false)]),
        (-16, [("문장", false), ("연결", true), ("커리어", false), ("발견", false)]),
        (-70, [("큐레이션", false), ("아카이브", false), ("길", true), ("튜토리얼", false)]),
        (-36, [("인터뷰", false), ("컬렉션", true), ("음악", false), ("기록", false)]),
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

                wordWall

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

    private var wordWall: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Self.wall.enumerated()), id: \.offset) { i, row in
                // 행은 overlay 로 붙인다 — fixedSize 행 폭이 레이아웃에 새어 나가면(특히 en/ja 처럼
                // 단어가 긴 로케일) 조상 VStack 이 화면보다 넓어져 페이지 전체가 왼쪽으로 밀린다.
                // overlay 는 조상 크기에 관여하지 않으니 어떤 언어여도 페이지 폭이 고정된다.
                Color.clear
                    .frame(height: 38)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 16) {
                            ForEach(Array(row.words.enumerated()), id: \.offset) { _, word in
                                Text(word.0)
                                    .font(.system(size: 32, weight: word.1 ? .heavy : .semibold))
                                    .foregroundStyle(word.1 ? Color.white : Color.white.opacity(0.32))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        .offset(x: row.offset)
                    }
                    .opacity(rowsVisible ? 1 : 0)
                    .offset(y: rowsVisible ? 0 : 8)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.05 * Double(i)),
                        value: rowsVisible)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        // 벽은 장식 — 보이스오버는 태그라인부터 읽는다.
        .accessibilityHidden(true)
    }

    // MARK: 엔트런스 — 벽이 줄줄이 서고, 태그라인·버튼이 한 박자씩 따라온다

    private func play() {
        guard !reduceMotion else {
            rowsVisible = true
            taglineVisible = true
            actionsVisible = true
            return
        }
        rowsVisible = true
        withAnimation(.easeOut(duration: 0.4).delay(0.34)) { taglineVisible = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.48)) { actionsVisible = true }
    }
}
