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

/// 이미지 — 실제 사진을 캔버스에서 바로 보인다(발행면 ImageBlockView 와 같은 RemoteImage 경로).
/// 로드 전·실패는 4:3 예약 박스로 자리를 지킨다(레이아웃 점프 방지). alt 는 아래 캡션 필드로 편집
/// (비텍스트 블록이라 본문 캐럿 규칙과 분리) — 왕복은 alt·url 만.
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
    /// 대체 텍스트 필드의 키보드 포커스 — 문서 focus 에 이 이미지 블록을 등록하는 방아쇠.
    /// 등록하지 않으면 문서 focus 가 직전 텍스트 블록에 남아, 첫 글자 입력(블록 배열 변경)의
    /// 뷰 갱신에서 그 텍스트 블록 UITextView 가 first responder 를 도로 뺏었다
    /// ("설명 한 글자 쓰면 다음 단락으로 이동"의 근본).
    @FocusState private var altFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            imageBody
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMini))
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
                .focused($altFocused)
                .onChange(of: altFocused) { _, focused in
                    if focused { onFocused() }
                }
                .onChange(of: alt) { _, new in onAltChange(new) }
        }
        .onAppear { alt = block.text }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("이미지"))
    }

    @ViewBuilder
    private var imageBody: some View {
        if let remote = URL(string: url), remote.scheme?.hasPrefix("http") == true {
            RemoteImage(url: remote, animation: .easeOut(duration: 0.35)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().transition(.opacity)
                case .failure:
                    placeholder(caption: String(localized: "이미지를 불러오지 못했어요"))
                default:
                    placeholder(caption: nil)
                }
            }
        } else {
            // http(s) 가 아닌 주소(목 픽스처 등)는 로드를 시도하지 않고 자리만 지킨다.
            placeholder(caption: nil)
        }
    }

    private func placeholder(caption: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.radiusMini)
                .fill(Palette.hairline)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Palette.faint)
                Text(caption ?? url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 24)
            }
        }
    }
}
