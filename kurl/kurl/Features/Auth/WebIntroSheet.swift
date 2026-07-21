//
//  WebIntroSheet.swift
//  kurl
//

import SwiftUI

/// 로그인 직후 딱 한 번 — "쓴 글이 웹에도 산다"를 내 주소로 보여주는 안내 시트.
/// 웰컴 연결 문법 그대로: 실(점→선)이 자라 주소 칩에 꽂히고, 칩을 탭하면 인앱
/// 사파리로 내 블로그가 열린다. 핸들이 있으면 blog.kurl.me/@핸들 로 개인화된다.
/// 표시 조건(1회·로그인 전환)은 RootView 가 든다 — 여기는 순수 표현.
struct WebIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var threadOn = false
    @State private var webLink: LegalLink?

    /// 핸들 포함 내 웹 주소 — 핸들이 아직 없으면 도메인만(방어).
    private var address: String {
        let handle = AuthStore.shared.me?.username ?? ""
        return handle.isEmpty ? "blog.kurl.me" : "blog.kurl.me/@\(handle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KurlMark(drawn: [true, true, true])
                .frame(width: 36, height: 22)
                .padding(.top, 28)

            Text("웹에서도 볼 수 있어요")
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(Palette.ink)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            Text("발행한 글은 웹에도 같은 글, 같은 주소로 살아요. 앱이 없어도 누구나 열 수 있어요.")
                .font(.system(size: 15 * unit))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            // 실 — 헤드라인에서 자라 내 주소 칩에 꽂힌다(웰컴·연결 카드와 같은 문법).
            VStack(spacing: 0) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.accent)
                    .frame(width: 2, height: 22)
            }
            .padding(.leading, 28)
            .padding(.top, 14)
            .scaleEffect(y: threadOn ? 1 : 0.01, anchor: .top)

            // 내 주소 칩 — 탭하면 인앱 사파리로 실제 내 블로그가 열린다(증명이 곧 안내).
            Button {
                if let url = URL(string: "https://\(address)") {
                    webLink = LegalLink(url: url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text(verbatim: address)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Palette.cardBg)
                        .shadow(color: .black.opacity(0.07), radius: 12, y: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Palette.accent.opacity(0.3), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .opacity(threadOn ? 1 : 0)
            .offset(y: threadOn ? 0 : -8)
            .accessibilityLabel("내 블로그 웹 주소 열기")

            Spacer(minLength: 20)

            Button {
                dismiss()
            } label: {
                Text("확인")
                    .font(.system(size: 16 * unit, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, Metrics.gutter + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.readingBg.ignoresSafeArea())
        .sheet(item: $webLink) { SafariView(url: $0.url).ignoresSafeArea() }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !reduceMotion else {
                threadOn = true
                return
            }
            withAnimation(.smooth(duration: 0.7).delay(0.35)) { threadOn = true }
        }
    }
}
