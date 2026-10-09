//
//  LoginSheet.swift
//  kurl
//

import SwiftUI

/// 앱의 유일한 로그인 표면 — 글쓰기 탭·계정 탭·인게이지가 모두 이 시트를 띄운다(`loginPrompt`).
/// 면마다 다른 건 안내 문구 한 줄뿐이고, 로그인이 끝나면 onSignedIn 후 시트를 닫는다.
struct LoginSheet: View {
    let message: LocalizedStringKey
    var onSignedIn: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(message)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                AuthProviderButtons {
                    await onSignedIn()
                    dismiss()
                }
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 32)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("login.sheet")
        .presentationDetents([.height(contentHeight), .large])
        .presentationDragIndicator(.visible)
    }
}
