//
//  BlockDividerImageView.swift
//  kurl — WriteV2 (Phase 2)
//
//  비텍스트 블록 두 종의 최종 모습 렌더 — 구분선(얇은 룰)·이미지(플레이스홀더+alt 캡션).
//  둘 다 캐럿을 담지 않는다(§4 재정의): 탭하면 선택(포커스)되고, 다음 문단에서의 백스페이스가
//  이 블록을 지운다(EditorDocument.mergeBackward 의 prev.isNonText 경로). 발행면(BlockRenderer)의
//  Hairline·ImageBlockView 와 같은 문법을 종이 세계(§1)에서 재현한다.
//

import SwiftUI

/// 구분선 — 발행면 `Hairline().padding(.vertical, 8)` 의 에디터 대응. 선택되면 은은한 강조.
struct BlockDividerView: View {
    let isFocused: Bool
    let onFocused: () -> Void

    var body: some View {
        Rectangle()
            .fill(isFocused ? Palette.accentSoft : Palette.hairlineStrong)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(.rect)
            .onTapGesture { onFocused() }
            .accessibilityElement()
            .accessibilityLabel(Text("구분선"))
    }
}

/// 이미지 — 로드는 Phase 2 스코프 밖(플레이스홀더 OK). url 을 라벨로 보이고 alt 를 캡션으로 편집한다.
/// alt 편집은 작은 텍스트필드(비텍스트 블록이라 본문 캐럿 규칙과 분리) — 왕복은 alt·url 만.
struct BlockImageView: View {
    let block: EditorBlock
    let isFocused: Bool
    let onAltChange: (String) -> Void
    let onFocused: () -> Void

    private var url: String {
        if case .image(let u) = block.kind { return u }
        return ""
    }

    @State private var alt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.radiusMini)
                    .fill(Palette.hairline)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Palette.faint)
                    Text(url)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 24)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusMini)
                    .strokeBorder(isFocused ? Palette.accentSoft : Color.clear, lineWidth: 2)
            )
            .contentShape(.rect)
            .onTapGesture { onFocused() }

            TextField("대체 텍스트", text: $alt)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .onChange(of: alt) { _, new in onAltChange(new) }
        }
        .onAppear { alt = block.text }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("이미지"))
    }
}
