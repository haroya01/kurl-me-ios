//
//  TakenDownNotice.swift
//  kurl
//

import SwiftUI

/// 운영 정책으로 내려진 글 안내 — 웹 에디터·발행 대화상자와 같은 문구.
struct TakenDownNotice: View {
    private var termsURL: URL? {
        URL(string: "\(Config.apiBase.absoluteString)/\(Config.preferredLanguageTag)/terms")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("운영 정책으로 내려진 글이에요")
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.danger)
            Text("고쳐서 저장할 수는 있지만 다시 공개할 수는 없어요. 이의가 있으면 이용약관의 문의처로 연락해 주세요.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.body)
                .fixedSize(horizontal: false, vertical: true)
            if let termsURL {
                Link("이용약관 보기", destination: termsURL)
                    .typeScale(.footnote)
                    .tint(Palette.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("takenDownNotice")
    }
}
