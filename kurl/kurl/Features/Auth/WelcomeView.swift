//
//  WelcomeView.swift
//  kurl
//

import SwiftUI

/// 첫 실행 1회 — 로그인 vs 게스트를 명시적으로 가른다. 게스트를 고르면 다시 안 뜬다.
/// 읽기는 로그인 뒤에 갇히면 안 되므로(App Store 5.1.1(v)) "둘러보기"가 동등한 1급 출구다.
/// 로그인 버튼 묶음은 계정 탭·글쓰기 게이트·로그인 시트와 같은 공유 컴포넌트.
struct WelcomeView: View {
    var onContinueAsGuest: () -> Void
    var onSignedIn: () -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            // 상단 옅은 브랜드 안개 — 계정 탭 로그인 패널과 같은 환대의 결.
            BrandMist()
                .frame(height: 380)
                .frame(maxHeight: .infinity, alignment: .top)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                KurlMark(drawn: [true, true, true])
                    .frame(width: 76, height: 46)
                Text(verbatim: "kurl")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-1.1)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 16)
                Text("읽고, 쓰고, 모으는 곳.")
                    .font(.system(size: 16 * unit))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)

                Spacer()

                AuthProviderButtons { onSignedIn() }

                Button {
                    onContinueAsGuest()
                } label: {
                    Text("로그인 없이 둘러보기")
                        .font(.system(size: 15 * unit, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter + 4)
            .padding(.bottom, 28)
        }
    }
}
