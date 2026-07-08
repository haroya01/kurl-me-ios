//
//  MarkdownIncrementalHighlighter.swift
//  kurl
//

import SwiftUI
import UIKit

/// 국소 재하이라이트 경로 — 캐럿 이동·펜스/표 안 타이핑이 매번 전체 문서 재스타일
/// (전문서 정규식 + 전범위 레이아웃 무효화)로 떨어지지 않게, 실제로 모습이 바뀌는 범위만
/// 다시 입힌다. 구조 경계(펜스 마커·표 안팎 전환)가 걸리면 false 를 돌려 호출측이
/// 전체 패스(apply)로 가게 한다 — 결과는 전체 패스와 같아야 한다.
extension MarkdownSyntaxHighlighter {
    /// 캐럿이 다른 문단으로 옮겨갈 때 — 떠난 문단(마커 숨김)과 새 문단(마커 노출)만 다시 입힌다.
    /// 펜스 안 줄은 캐럿이 있든 없든 같은 코드색이라 건너뛰고, 펜스 마커 줄과 표(파이프) 줄은
    /// 경계·그리드↔원시 전환에 전체 문맥이 필요해 false(전체 패스로).
    static func applyCaretMove(to textView: UITextView, fromParagraphAt previousStart: Int) -> Bool {
        guard textView.markedTextRange == nil else { return false }
        let ns = textView.text as NSString
        guard ns.length > 0 else { return false }
        let caret = min(textView.selectedRange.location, ns.length)
        let newPara = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        let oldPara = ns.paragraphRange(
            for: NSRange(location: min(max(0, previousStart), ns.length), length: 0))
        var repaint: [NSRange] = []
        for para in (oldPara == newPara ? [newPara] : [oldPara, newPara]) {
            let s = ns.substring(with: para)
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return false }
            if fenceOpen(before: para.location, ns: ns) { continue }
            if s.contains("`") || s.contains("~") || s.contains("|") { return false }
            repaint.append(para)
        }
        if !repaint.isEmpty {
            let storage = textView.textStorage
            let selected = textView.selectedRange
            let width = availableWidth(textView)
            storage.beginEditing()
            for para in repaint where para.length > 0 {
                storage.setAttributes(baseAttributes(), range: para)
                styleLines(storage, ns, in: para, activePara: newPara, startInFence: false, startMarker: nil)
                applyImages(storage, ns, in: para, width: width)
            }
            storage.endEditing()
            if selected.location <= ns.length { textView.selectedRange = selected }
        }
        textView.typingAttributes = baseAttributes()
        return true
    }

    /// 코드펜스 안(마커 줄 제외) 문단의 편집 — 그 문단만 코드색으로 다시 칠한다. 마커 줄이거나
    /// 펜스 밖이면 false. 마커 줄 자체를 바꾸는 편집(경계 이동)은 shouldChangeTextIn 의
    /// 전체 패스 표시가 이 경로에 오기 전에 걸러 준다.
    static func applyFenceInteriorEdit(to textView: UITextView) -> Bool {
        guard textView.markedTextRange == nil else { return false }
        let ns = textView.text as NSString
        guard ns.length > 0 else { return false }
        let caret = min(textView.selectedRange.location, ns.length)
        let para = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        let trimmed = ns.substring(with: para).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("```"), !trimmed.hasPrefix("~~~"),
            fenceOpen(before: para.location, ns: ns)
        else { return false }
        let storage = textView.textStorage
        let selected = textView.selectedRange
        // 줄바꿈을 뺀 본문 범위 — 전체 패스(styleLines 의 byLines)와 같은 범위에만 코드색을 입힌다.
        var contentLen = para.length
        while contentLen > 0 {
            let c = ns.substring(with: NSRange(location: para.location + contentLen - 1, length: 1))
            if c == "\n" || c == "\r" { contentLen -= 1 } else { break }
        }
        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: para)
        if contentLen > 0 {
            let content = NSRange(location: para.location, length: contentLen)
            storage.addAttribute(.backgroundColor, value: UIColor(Palette.codeBg), range: content)
            storage.addAttribute(.foregroundColor, value: UIColor(Palette.codeText), range: content)
        }
        // 전체 패스는 펜스 안 whole-line 이미지도 숨겨 썸네일로 그린다 — 같은 결과를 유지.
        applyImages(storage, ns, in: para, width: availableWidth(textView))
        storage.endEditing()
        if selected.location <= ns.length { textView.selectedRange = selected }
        textView.typingAttributes = baseAttributes()
        return true
    }

    /// 캐럿 문단이 파이프 줄(표 후보)일 때의 편집 — 캐럿을 품은 연속 파이프-줄 블록만 다시
    /// 입힌다(GFM 표는 이 블록을 넘지 못한다). 블록에 백틱·물결이 섞이거나 펜스 안이면 false.
    static func applyTableRegionEdit(to textView: UITextView) -> Bool {
        guard textView.markedTextRange == nil else { return false }
        let ns = textView.text as NSString
        guard ns.length > 0 else { return false }
        let caret = min(textView.selectedRange.location, ns.length)
        let activePara = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        func rejects(_ s: String) -> Bool { s.contains("`") || s.contains("~") }
        let paraStr = ns.substring(with: activePara)
        guard paraStr.contains("|"), !rejects(paraStr) else { return false }
        // 위아래로 파이프 줄이 이어지는 만큼 블록을 넓힌다 — 빈 줄·파이프 없는 줄에서 표가 끊긴다.
        var start = activePara.location
        var end = activePara.location + activePara.length
        while start > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: start - 1, length: 0))
            let s = ns.substring(with: prev)
            guard s.contains("|"),
                !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { break }
            if rejects(s) { return false }
            start = prev.location
        }
        while end < ns.length {
            let next = ns.paragraphRange(for: NSRange(location: end, length: 0))
            let s = ns.substring(with: next)
            guard s.contains("|"),
                !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { break }
            if rejects(s) { return false }
            end = next.location + next.length
        }
        guard !fenceOpen(before: start, ns: ns) else { return false }
        let region = NSRange(location: start, length: end - start)
        let storage = textView.textStorage
        let selected = textView.selectedRange
        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: region)
        styleLines(storage, ns, in: region, activePara: activePara, startInFence: false, startMarker: nil)
        applyImages(storage, ns, in: region, width: availableWidth(textView))
        applyTables(storage, ns, in: region, activePara: activePara)
        storage.endEditing()
        if selected.location <= ns.length { textView.selectedRange = selected }
        textView.typingAttributes = baseAttributes()
        return true
    }
}
