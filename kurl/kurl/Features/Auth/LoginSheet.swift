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
    @State private var contentHeight: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 작은 브랜드 마크 — 시트가 "kurl 의 것"임을 한눈에.
            KurlMark(drawn: [true, true, true])
                .frame(width: 40, height: 24)
                .padding(.bottom, 16)

            // 안내 문구가 곧 제목 — "계정으로 이어집니다" 류 보일러플레이트·"안전하게
            // 진행됩니다" 류 과잉 안심을 걷고, 그 순간의 행동 가치 한 줄만 남긴다.
            Text(message)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            AuthProviderButtons {
                await onSignedIn()
                dismiss()
            }
            .padding(.top, 24)
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
