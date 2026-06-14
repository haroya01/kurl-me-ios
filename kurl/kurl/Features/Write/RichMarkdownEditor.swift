//
//  RichMarkdownEditor.swift
//  kurl
//

import SwiftUI
import UIKit

// MARK: 마크다운 ⇄ 속성문자열 (Phase 1: 제목 H1~H3 · 굵게 · 기울임 · 인라인 코드)

/// WYSIWYG 에디터의 문서 모델 = NSAttributedString(서식이 실제 속성, 기호 안 보임).
/// 마크다운은 저장 직렬화일 뿐. **Phase 1 은 제목·굵게·기울임·인라인 코드만** WYSIWYG —
/// 그 외 문법(리스트·인용·코드블록·링크·이미지)은 평문으로 왕복한다(Phase 2~3).
enum RichMarkdown {
    static let headingKey = NSAttributedString.Key("kurl.headingLevel")
    static let codeKey = NSAttributedString.Key("kurl.inlineCode")

    static func bodyFont(_ size: CGFloat = 16, bold: Bool = false, italic: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let d = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 26
        case 2: return 22
        default: return 19
        }
    }

    static func codeFont(_ size: CGFloat) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: max(12, size - 1), weight: .regular)
    }

    static let codeBackground = UIColor(white: 0.5, alpha: 0.14)

    // MARK: parse — markdown → attributed

    static func attributed(from markdown: String, color: UIColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let (level, content) = headingSplit(line)
            out.append(inlineAttributed(content, color: color, heading: level))
            if i < lines.count - 1 {
                out.append(NSAttributedString(
                    string: "\n", attributes: [.font: bodyFont(), .foregroundColor: color]))
            }
        }
        return out
    }

    private static func headingSplit(_ line: String) -> (Int, String) {
        if line.hasPrefix("### ") { return (3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ") { return (2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ") { return (1, String(line.dropFirst(2))) }
        return (0, line)
    }

    /// 한 줄의 인라인 마크다운(**굵게**·*기울임*·`코드`)을 속성문자열로. heading>0 이면 제목.
    private static func inlineAttributed(_ text: String, color: UIColor, heading: Int) -> NSAttributedString {
        let size = heading > 0 ? headingSize(heading) : 16
        let headingBold = heading > 0
        let out = NSMutableAttributedString()
        let chars = Array(text)
        var bold = false, italic = false, buffer = ""

        func attrs(code: Bool) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if heading > 0 { a[headingKey] = heading }
            if code {
                a[.font] = codeFont(size)
                a[.backgroundColor] = codeBackground
                a[codeKey] = true
            } else {
                a[.font] = bodyFont(size, bold: bold || headingBold, italic: italic)
            }
            return a
        }
        func flush(code: Bool = false) {
            guard !buffer.isEmpty else { return }
            out.append(NSAttributedString(string: buffer, attributes: attrs(code: code)))
            buffer = ""
        }

        var i = 0
        while i < chars.count {
            if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                flush(); bold.toggle(); i += 2; continue
            }
            if chars[i] == "*" || chars[i] == "_" {
                flush(); italic.toggle(); i += 1; continue
            }
            if chars[i] == "`" {
                flush()
                i += 1
                var code = ""
                while i < chars.count, chars[i] != "`" { code.append(chars[i]); i += 1 }
                if i < chars.count { i += 1 }
                buffer = code
                flush(code: true)
                continue
            }
            buffer.append(chars[i]); i += 1
        }
        flush()
        // 빈 줄도 한 글자 폭은 있어야 캐럿이 선다.
        if out.length == 0 {
            out.append(NSAttributedString(string: "", attributes: attrs(code: false)))
        }
        return out
    }

    // MARK: serialize — attributed → markdown

    static func markdown(from attr: NSAttributedString) -> String {
        let plain = attr.string
        var lines: [String] = []
        var location = 0
        for line in plain.components(separatedBy: "\n") {
            let len = (line as NSString).length
            var level = 0
            if len > 0 {
                level = (attr.attribute(headingKey, at: location, effectiveRange: nil) as? Int) ?? 0
            }
            let prefix = level > 0 ? String(repeating: "#", count: level) + " " : ""
            let body = inlineMarkdown(attr.attributedSubstring(from: NSRange(location: location, length: len)))
            lines.append(prefix + body)
            location += len + 1
        }
        return lines.joined(separator: "\n")
    }

    private static func inlineMarkdown(_ attr: NSAttributedString) -> String {
        var md = ""
        var openBold = false, openItalic = false
        func close() {
            if openItalic { md += "*"; openItalic = false }
            if openBold { md += "**"; openBold = false }
        }
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { a, range, _ in
            let sub = (attr.string as NSString).substring(with: range)
            if a[codeKey] != nil {
                close()
                md += "`\(sub)`"
                return
            }
            let traits = (a[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            // 제목의 굵기는 #·문법이지 ** 가 아니다 — heading 런은 ** 로 감싸지 않는다.
            let isBold = traits.contains(.traitBold) && a[headingKey] == nil
            let isItalic = traits.contains(.traitItalic)
            if isItalic != openItalic { md += "*"; openItalic = isItalic }
            if isBold != openBold { md += "**"; openBold = isBold }
            md += sub
        }
        close()
        return md
    }
}

// MARK: 에디터 뷰

/// WYSIWYG 마크다운 캔버스 — 입력칸엔 서식이 실제로 보이고(기호 숨김), 저장은 마크다운.
/// 조합(markedText) 중에는 외부 쓰기·재스타일을 전면 보류한다(한글 입력 보호 — 기존 교훈).
struct RichMarkdownEditor: UIViewRepresentable {
    @Binding var markdown: String
    let controller: RichEditorController
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.autocapitalizationType = .sentences
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        tv.delegate = context.coordinator
        tv.typingAttributes = [.font: RichMarkdown.bodyFont(), .foregroundColor: UIColor(Palette.body)]
        tv.attributedText = RichMarkdown.attributed(from: markdown, color: UIColor(Palette.body))
        controller.textView = tv
        controller.onChange = { context.coordinator.pushBinding(tv) }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // 외부 변경(리비전 복원·정규화)은 조합이 끝난 뒤에만, 내가 만든 변경이 아닐 때만.
        guard tv.markedTextRange == nil else { return }
        if RichMarkdown.markdown(from: tv.attributedText) != markdown {
            let sel = tv.selectedRange
            tv.attributedText = RichMarkdown.attributed(from: markdown, color: UIColor(Palette.body))
            let limit = tv.attributedText.length
            tv.selectedRange = NSRange(location: min(sel.location, limit), length: 0)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: RichMarkdownEditor

        init(_ parent: RichMarkdownEditor) { self.parent = parent }

        /// 직렬화 → 바인딩(자동저장). 조합 중간값은 안 흘린다.
        func pushBinding(_ tv: UITextView) {
            guard tv.markedTextRange == nil else { return }
            parent.markdown = RichMarkdown.markdown(from: tv.attributedText)
        }

        func textViewDidChange(_ tv: UITextView) { pushBinding(tv) }

        func textViewDidChangeSelection(_ tv: UITextView) {
            // 커서 위치의 서식을 이어 타이핑에 물려준다(제목 줄 안에서 계속 치면 제목 유지).
            guard tv.markedTextRange == nil else { return }
            let loc = tv.selectedRange.location
            if loc > 0, loc <= tv.attributedText.length {
                let attrs = tv.attributedText.attributes(at: loc - 1, effectiveRange: nil)
                var typing = attrs
                typing[.backgroundColor] = attrs[RichMarkdown.codeKey] != nil ? RichMarkdown.codeBackground : nil
                tv.typingAttributes = typing
            }
        }

        func textViewDidBeginEditing(_ tv: UITextView) { parent.onFocusChange(true) }

        func textViewDidEndEditing(_ tv: UITextView) {
            pushBinding(tv)
            parent.onFocusChange(false)
        }
    }
}

// MARK: 컨트롤러 — 툴바가 선택/커서에 서식 적용

@MainActor
final class RichEditorController {
    weak var textView: UITextView?
    var onChange: (() -> Void)?

    var currentMarkdown: String {
        guard let tv = textView else { return "" }
        return RichMarkdown.markdown(from: tv.attributedText)
    }

    func focus() { textView?.becomeFirstResponder() }
    func dismissKeyboard() { textView?.resignFirstResponder() }

    func toggleBold() { toggleTrait(.traitBold) }
    func toggleItalic() { toggleTrait(.traitItalic) }

    func toggleInlineCode() {
        guard let tv = textView, tv.markedTextRange == nil else { return }
        let range = tv.selectedRange
        guard range.length > 0 else { return }
        let isCode = tv.attributedText.attribute(RichMarkdown.codeKey, at: range.location, effectiveRange: nil) != nil
        let size = headingLevel(at: range.location) > 0 ? RichMarkdown.headingSize(headingLevel(at: range.location)) : 16
        tv.textStorage.beginEditing()
        if isCode {
            tv.textStorage.removeAttribute(RichMarkdown.codeKey, range: range)
            tv.textStorage.removeAttribute(.backgroundColor, range: range)
            tv.textStorage.addAttribute(.font, value: RichMarkdown.bodyFont(size), range: range)
        } else {
            tv.textStorage.addAttribute(RichMarkdown.codeKey, value: true, range: range)
            tv.textStorage.addAttribute(.backgroundColor, value: RichMarkdown.codeBackground, range: range)
            tv.textStorage.addAttribute(.font, value: RichMarkdown.codeFont(size), range: range)
        }
        tv.textStorage.endEditing()
        tv.selectedRange = range
        onChange?()
    }

    /// 현재 문단(들)의 제목 레벨 토글 — 같은 레벨을 다시 누르면 본문으로.
    func toggleHeading(_ level: Int) {
        guard let tv = textView, tv.markedTextRange == nil else { return }
        let para = (tv.text as NSString).paragraphRange(for: tv.selectedRange)
        let current = headingLevel(at: para.location)
        let target = current == level ? 0 : level
        let size = target > 0 ? RichMarkdown.headingSize(target) : 16
        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttributes(in: para) { a, sub, _ in
            if a[RichMarkdown.codeKey] != nil { return }
            let italic = ((a[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []).contains(.traitItalic)
            let boldRun = target == 0
                && ((a[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []).contains(.traitBold)
                && a[RichMarkdown.headingKey] == nil
            tv.textStorage.addAttribute(
                .font, value: RichMarkdown.bodyFont(size, bold: target > 0 || boldRun, italic: italic), range: sub)
            if target > 0 {
                tv.textStorage.addAttribute(RichMarkdown.headingKey, value: target, range: sub)
            } else {
                tv.textStorage.removeAttribute(RichMarkdown.headingKey, range: sub)
            }
        }
        tv.textStorage.endEditing()
        tv.selectedRange = tv.selectedRange
        onChange?()
    }

    /// Phase 1 미지원 서식 — 평문 마크다운을 커서 자리에 넣는다(리스트·인용·코드블록·링크·이미지).
    func insertPlain(_ text: String, caretBackBy: Int = 0) {
        guard let tv = textView, tv.markedTextRange == nil, let sel = tv.selectedTextRange else { return }
        let start = tv.selectedRange.location
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RichMarkdown.bodyFont(), .foregroundColor: UIColor(Palette.body),
        ]
        tv.textStorage.replaceCharacters(
            in: tv.selectedRange, with: NSAttributedString(string: text, attributes: attrs))
        let end = start + (text as NSString).length - caretBackBy
        tv.selectedRange = NSRange(location: max(0, end), length: 0)
        onChange?()
    }

    private func headingLevel(at location: Int) -> Int {
        guard let tv = textView, location < tv.attributedText.length else { return 0 }
        return (tv.attributedText.attribute(RichMarkdown.headingKey, at: location, effectiveRange: nil) as? Int) ?? 0
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView, tv.markedTextRange == nil else { return }
        let range = tv.selectedRange
        if range.length == 0 {
            var typing = tv.typingAttributes
            let font = (typing[.font] as? UIFont) ?? RichMarkdown.bodyFont()
            typing[.font] = toggled(font, trait: trait, on: !font.fontDescriptor.symbolicTraits.contains(trait))
            tv.typingAttributes = typing
            return
        }
        var allOn = true
        tv.attributedText.enumerateAttribute(.font, in: range) { v, _, _ in
            let f = (v as? UIFont) ?? RichMarkdown.bodyFont()
            if !f.fontDescriptor.symbolicTraits.contains(trait) { allOn = false }
        }
        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.font, in: range) { v, sub, _ in
            let f = (v as? UIFont) ?? RichMarkdown.bodyFont()
            tv.textStorage.addAttribute(.font, value: toggled(f, trait: trait, on: !allOn), range: sub)
        }
        tv.textStorage.endEditing()
        tv.selectedRange = range
        onChange?()
    }

    private func toggled(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits, on: Bool) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if on { traits.insert(trait) } else { traits.remove(trait) }
        if let d = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: d, size: font.pointSize)
        }
        return font
    }
}
