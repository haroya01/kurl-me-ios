//
//  LoginSheet.swift
//  kurl
//

import SwiftUI

/// 인게이지(좋아요·북마크·팔로우·구독·태그·댓글)에서 비로그인일 때 그 자리에서 뜨는 정식 로그인 시트.
/// 알럿(텍스트 버튼)이 아니라 본문 한 장 + 공식 Apple/Google 버튼 — HIG 권장 모양 그대로.
/// 면마다 다른 건 안내 문구뿐이고, 로그인이 끝나면 onSignedIn(보통 hydrate) 후 시트를 닫는다.
/// 시트는 콘텐츠 높이에 딱 맞는 detent 로 떠 — .medium 의 빈 공간을 두지 않는다.
struct LoginSheet: View {
    let message: LocalizedStringKey
    var onSignedIn: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var contentHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 작은 브랜드 마크 — 시트가 "kurl 의 것"임을 한눈에.
            KurlMark(drawn: [true, true, true])
                .frame(width: 40, height: 24)
                .padding(.bottom, 14)

            Text("kurl 계정으로 이어집니다")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(Palette.ink)

            Text(message)
                .font(.system(size: 15 * unit))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(4)
                .padding(.top, 8)

            AuthProviderButtons {
                await onSignedIn()
                dismiss()
            }
            .padding(.top, 22)

            Text("로그인은 시스템 브라우저에서 안전하게 진행됩니다.")
                .font(.system(size: 12 * metaUnit))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
        .padding(.bottom, 24)
        // 콘텐츠 높이를 재 그만큼만 시트를 띄운다 — Dynamic Type 가 커지면 detent 도 따라 큰다.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }
}
