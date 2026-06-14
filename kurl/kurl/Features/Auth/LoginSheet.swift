//
//  LoginSheet.swift
//  kurl
//

import SwiftUI

/// 인게이지(좋아요·북마크·팔로우·구독·태그·댓글)에서 비로그인일 때 그 자리에서 뜨는 정식 로그인 시트.
/// 알럿(텍스트 버튼)이 아니라 본문 한 장 + 공식 Apple/Google 버튼 — HIG 권장 모양 그대로.
/// 면마다 다른 건 안내 문구뿐이고, 로그인이 끝나면 onSignedIn(보통 hydrate) 후 시트를 닫는다.
struct LoginSheet: View {
    let message: LocalizedStringKey
    var onSignedIn: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.top, 24)

            Text("로그인은 시스템 브라우저에서 안전하게 진행됩니다.")
                .font(.system(size: 12 * metaUnit))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 32)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
