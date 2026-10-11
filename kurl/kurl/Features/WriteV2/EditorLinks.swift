//
//  EditorLinks.swift
//  kurl — WriteV2
//

import UIKit

struct EditorLinkSpan: Equatable {
    let range: NSRange
    let labelRange: NSRange
    let label: String
    let url: String
}

struct EditorLinkTarget: Equatable {
    let blockID: UUID
    let range: NSRange
    let original: String
    let label: String?
    let shownText: String
    let url: String

    var editing: Bool { !url.isEmpty }
    var canPickCard: Bool { range.length == 0 && !editing }

    static func editing(_ span: EditorLinkSpan, in blockID: UUID, text: String) -> EditorLinkTarget {
        let autolink = span.label == span.url
        return EditorLinkTarget(
            blockID: blockID, range: span.range, original: (text as NSString).substring(with: span.range),
            label: autolink ? nil : span.label,
            shownText: autolink ? "" : EditorLinkMarkup.visibleText(span.label), url: span.url)
    }
}

struct EditorLinkHandlers {
    var open: ((URL) -> Void)?
    var edit: ((EditorLinkTarget) -> Void)?
}

enum EditorPastePlan: Equatable {
    case plain
    case image(url: String)
    case linkSelection(url: String)
    case relink(EditorLinkSpan, url: String)
    case linkWithChoice(url: String, video: Bool)
    case linkInline(url: String)
}

enum EditorLinkMarkup {
    /// Web and the server read `<url>` and `[text](url)` as a link; only a bare URL alone on its line is a card.
    static func markup(label: String, url: String) -> String {
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == url ? "<\(url)>" : "[\(text)](\(url))"
    }

    static func spans(in text: String) -> [EditorLinkSpan] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let code = BlockInlineRenderer.codeRegex.matches(in: text, range: full).map(\.range)
        func free(_ range: NSRange) -> Bool {
            !code.contains { NSIntersectionRange($0, range).length > 0 }
        }
        var spans: [EditorLinkSpan] = []
        for m in BlockInlineRenderer.linkRegex.matches(in: text, range: full) where free(m.range) {
            spans.append(EditorLinkSpan(
                range: m.range, labelRange: m.range(at: 1),
                label: ns.substring(with: m.range(at: 1)), url: ns.substring(with: m.range(at: 2))))
        }
        for m in BlockInlineRenderer.autolinkRegex.matches(in: text, range: full) where free(m.range) {
            guard !spans.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) else { continue }
            let url = ns.substring(with: m.range(at: 1))
            spans.append(EditorLinkSpan(range: m.range, labelRange: m.range(at: 1), label: url, url: url))
        }
        return spans.sorted { $0.range.location < $1.range.location }
    }

    static func span(atLabel location: Int, in text: String) -> EditorLinkSpan? {
        spans(in: text).first { location >= $0.labelRange.location && location < NSMaxRange($0.labelRange) }
    }

    static func span(around caret: Int, in text: String) -> EditorLinkSpan? {
        spans(in: text).first { caret > $0.range.location && caret < NSMaxRange($0.range) }
    }

    static func plan(
        pasted: String, kind: EditorBlockKind, text: String, selection: NSRange, canImportImage: Bool
    ) -> EditorPastePlan {
        guard let url = MarkdownInputTextView.singleURL(in: pasted) else { return .plain }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let links = spans(in: text)
        if selection.length > 0, let link = links.first(where: {
            selection.location >= $0.labelRange.location && NSMaxRange(selection) <= NSMaxRange($0.labelRange)
        }) {
            return .relink(link, url: url)
        }
        let markup = BlockInlineRenderer.codeRegex.matches(in: text, range: full).map(\.range) + links.map(\.range)
        let insideMarkup = markup.contains { span in
            selection.length > 0
                ? NSIntersectionRange(span, selection).length > 0
                : selection.location > span.location && selection.location < NSMaxRange(span)
        }
        if insideMarkup { return .plain }
        if selection.length > 0 { return .linkSelection(url: url) }
        if canImportImage, MarkdownInputTextView.isImageURL(url) { return .image(url: url) }
        if kind == .paragraph, text.isEmpty {
            return .linkWithChoice(url: url, video: WriteV2VideoDetect.isVideoURL(url))
        }
        return .linkInline(url: url)
    }

    static func visibleText(_ raw: String) -> String {
        let rendered = BlockInlineRenderer.render(EditorBlock(kind: .paragraph, text: raw))
        var visible = ""
        rendered.enumerateAttribute(.font, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
            if let font = value as? UIFont, font.pointSize < 1 { return }
            visible += rendered.attributedSubstring(from: range).string
        }
        return visible
    }
}
