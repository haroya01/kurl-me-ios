//
//  BlockCodeView.swift
//  kurl — WriteV2
//
//  코드 블록 — 최종 모습(어두운 모노 박스 + 언어 라벨)으로 렌더하며 그 안에서 바로 편집한다.
//  원시 ``` 펜스는 안 보인다(블록 종류가 코드임을 박스가 말한다). 편집 UITextView 는 개행을
//  블록 분할로 승격하지 않는다 — 코드 블록 안 엔터는 진짜 개행이다(§4 어려운 지점).
//
//  Phase 1 은 편집 중 실시간 신택스 색은 생략하고 모노 plain 으로 편집(읽기면 BlockRenderer 가
//  발행 후 CodeSyntax 로 색칠). 박스·언어 라벨·모노는 발행면과 같은 문법(§1 종이 세계 컨트롤 면).
//

import SwiftUI
import UIKit

struct BlockCodeView: View {
    let block: EditorBlock
    let isFocused: Bool
    let onTextChange: (String) -> Void
    let onFocused: () -> Void
    /// 빈 코드 블록 맨 앞 백스페이스 → 문단으로 강등/병합(문서가 처리).
    let onMergeBackward: () -> Void

    private var language: String? {
        if case .code(let lang) = block.kind { return lang }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.codeText.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.top, 11)
                    .padding(.bottom, 2)
            }
            CodeEditingTextView(
                text: block.text,
                language: language,
                isFocused: isFocused,
                onTextChange: onTextChange,
                onFocused: onFocused,
                onMergeBackward: onMergeBackward
            )
            .padding(.horizontal, 14)
            .padding(.top, language == nil ? 12 : 4)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.codeBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusControl)
                .strokeBorder(Palette.hairlineStrong.opacity(0.4), lineWidth: 1)
        )
    }
}

/// 코드 편집 UITextView — 모노 + 언어별 신택스 컬러(발행 리더의 CodeSyntax 워커 공유 — 편집 중
/// 보던 색이 발행 후에도 같다). 개행은 분할 아님(진짜 개행). 맨 앞 백스페이스만 병합 승격.
private struct CodeEditingTextView: UIViewRepresentable {
    let text: String
    let language: String?
    let isFocused: Bool
    let onTextChange: (String) -> Void
    let onFocused: () -> Void
    let onMergeBackward: () -> Void

    static let monoFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    func makeUIView(context: Context) -> BlockUITextView {
        let tv = BlockUITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.font = Self.monoFont
        tv.textColor = UIColor(Palette.codeText)
        tv.text = text
        tv.currentBlockText = text
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.applyHighlight(tv)
        return tv
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fit.height)
    }

    func updateUIView(_ tv: BlockUITextView, context: Context) {
        context.coordinator.parent = self
        if tv.currentBlockText != text {
            tv.text = text
            tv.currentBlockText = text
            context.coordinator.applyHighlight(tv)
        }
        if isFocused, !tv.isFirstResponder { tv.becomeFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditingTextView
        init(_ parent: CodeEditingTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocused() }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            // 빈 코드 블록 맨 앞 백스페이스 → 강등/병합.
            if text.isEmpty, range.length == 1, range.location == 0,
               (textView.text ?? "").isEmpty {
                parent.onMergeBackward()
                return false
            }
            return true // 엔터 포함 모든 입력은 진짜 텍스트(코드 안 개행).
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let tv = textView as? BlockUITextView else { return }
            tv.currentBlockText = tv.text ?? ""
            parent.onTextChange(tv.text ?? "")
            // 신택스 재채색은 조합이 끝난 뒤에만(조합 중 attributedText 교체는 한글 IME 를 깬다).
            if tv.markedTextRange == nil {
                applyHighlight(tv)
            }
        }

        /// 언어별 신택스 컬러 — 캐럿을 보존한 채 전체를 다시 칠한다(리더 CodeSyntax 워커 공유,
        /// 6000자 초과는 워커가 plain 단색으로 흘려 비용을 막는다).
        func applyHighlight(_ tv: BlockUITextView) {
            let selected = tv.selectedRange
            tv.attributedText = CodeSyntax.nsHighlight(
                tv.text ?? "", lang: parent.language, font: CodeEditingTextView.monoFont)
            if selected.location + selected.length <= (tv.text as NSString).length {
                tv.selectedRange = selected
            }
            tv.typingAttributes = [
                .font: CodeEditingTextView.monoFont,
                .foregroundColor: UIColor(Palette.codeText),
            ]
        }
    }
}
