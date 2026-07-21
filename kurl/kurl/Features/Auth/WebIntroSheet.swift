//
//  WebIntroSheet.swift
//  kurl
//

import SwiftUI

/// 로그인 직후 딱 한 번 — "쓴 글이 웹에도 산다"를 내 주소로 보여주는 안내 시트.
/// 웰컴과 같은 실크 엔트런스: 마크 3바가 그려지고, 문장이 서고, 실이 자라 내 주소 칩에
/// 꽂힌 뒤 주소 위로 형광이 긋듯 스윕한다(kurl 고유 제스처). 칩을 탭하면 인앱 사파리로
/// 실제 내 블로그가 열린다 — 안내가 곧 증명. 표시 조건(1회·로그인 전환)은 RootView 몫.
struct WebIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var markDrawn: [Bool] = [false, false, false]
    @State private var headOn = false
    @State private var bodyOn = false
    @State private var threadOn = false
    @State private var sweepOn = false
    @State private var footOn = false
    @State private var actionsOn = false
    @State private var webLink: LegalLink?

    /// 핸들 포함 내 웹 주소 — 핸들이 아직 없으면 도메인만(방어).
    private var address: String {
        let handle = AuthStore.shared.me?.username ?? ""
        return handle.isEmpty ? "blog.kurl.me" : "blog.kurl.me/@\(handle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KurlMark(drawn: markDrawn)
                .frame(width: 36, height: 22)
                .padding(.top, 28)

            Text("웹에서도 볼 수 있어요")
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(Palette.ink)
                .padding(.top, 18)
                .opacity(headOn ? 1 : 0)
                .offset(y: headOn ? 0 : 10)
                .blur(radius: headOn ? 0 : 2)
                .accessibilityAddTraits(.isHeader)

            Text("여기서 발행하면 그 순간 웹에도 살아요 — 같은 글, 같은 주소. 앱이 없어도 누구나 브라우저로 읽어요.")
                .font(.system(size: 15 * unit))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .opacity(bodyOn ? 1 : 0)
                .offset(y: bodyOn ? 0 : 8)

            // 실 — 문장에서 자라 내 주소 칩에 꽂힌다(웰컴·연결 카드와 같은 문법).
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
            .opacity(threadOn ? 1 : 0)

            // 내 주소 칩 — 탭하면 인앱 사파리로 실제 내 블로그가 열린다(증명이 곧 안내).
            // 주소 위로 형광이 긋듯 스윕 — 인앱 하이라이트와 같은 결.
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
                        .padding(.horizontal, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.accent.opacity(0.14))
                                .scaleEffect(x: sweepOn ? 1 : 0.001, anchor: .leading))
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

            // 갓 만든 계정의 웹은 아직 비어 있다 — 열어 보기 전에 기대를 맞춰 준다.
            Text("첫 글을 발행하면 이 주소가 채워져요.")
                .font(.system(size: 13 * unit))
                .foregroundStyle(Palette.faint)
                .padding(.top, 10)
                .padding(.leading, 16)
                .opacity(footOn ? 1 : 0)

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
            .opacity(actionsOn ? 1 : 0)
            .offset(y: actionsOn ? 0 : 10)
        }
        .padding(.horizontal, Metrics.gutter + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.readingBg.ignoresSafeArea())
        .sheet(item: $webLink) { SafariView(url: $0.url).ignoresSafeArea() }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { play() }
    }

    /// 실크 엔트런스 — 마크가 그려지고, 문장이 서고, 실이 자라고, 주소에 형광이 긋는다.
    /// 버튼은 일찍(0.55s) 서서 CTA 를 기다리게 하지 않는다.
    private func play() {
        guard !reduceMotion else {
            markDrawn = [true, true, true]
            headOn = true
            bodyOn = true
            threadOn = true
            sweepOn = true
            footOn = true
            actionsOn = true
            return
        }
        let silk = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)
        for i in 0..<3 {
            withAnimation(.smooth(duration: 0.45).delay(0.05 + Double(i) * 0.1)) { markDrawn[i] = true }
        }
        withAnimation(silk.delay(0.25)) { headOn = true }
        withAnimation(silk.delay(0.4)) { bodyOn = true }
        withAnimation(silk.delay(0.55)) { actionsOn = true }
        withAnimation(.smooth(duration: 0.7).delay(0.75)) { threadOn = true }
        withAnimation(.smooth(duration: 0.6).delay(1.3)) { sweepOn = true }
        withAnimation(silk.delay(1.5)) { footOn = true }
    }
}
