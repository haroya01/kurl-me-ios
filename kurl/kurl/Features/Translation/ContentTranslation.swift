//
//  ContentTranslation.swift
//  kurl
//

import NaturalLanguage
import SwiftUI
import Translation

nonisolated enum TranslationGate {
    static let minimumLetters = 8
    static let minimumConfidence = 0.85

    static func source(declared: String?, text: String, preferred: [String] = Locale.preferredLanguages) -> Locale.Language? {
        let code = declared.flatMap { languageCode($0) } ?? detect(text)
        guard let code, !preferred.contains(where: { languageCode($0) == code }) else { return nil }
        return Locale.Language(identifier: code)
    }

    static func detect(_ text: String) -> String? {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= minimumLetters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined, confidence >= minimumConfidence
        else { return nil }
        return languageCode(language.rawValue)
    }

    static func languageCode(_ identifier: String) -> String? {
        let code = Locale.Language(identifier: identifier).languageCode?.identifier
        return (code?.isEmpty ?? true) ? nil : code
    }

    static func target(preferred: [String] = Locale.preferredLanguages) -> Locale.Language {
        Locale.Language(identifier: preferred.first ?? "ko")
    }

    static func displayName(_ language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? ""
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

// MARK: 노트

enum NoteTranslation {
    enum Part: Equatable {
        case text(String)
        case token(String)
    }

    static func parts(_ body: String) -> [Part] {
        let ns = body as NSString
        var parts: [Part] = []
        var last = 0
        for range in NoteText.tokenRanges(in: body) {
            if range.location > last {
                parts.append(.text(ns.substring(with: NSRange(location: last, length: range.location - last))))
            }
            parts.append(.token(ns.substring(with: range)))
            last = range.location + range.length
        }
        if last < ns.length { parts.append(.text(ns.substring(from: last))) }
        return parts
    }

    static func requests(_ parts: [Part]) -> [String] {
        parts.compactMap { part in
            guard case let .text(text) = part else { return nil }
            let core = Trimmed(text).core
            return core.unicodeScalars.contains(where: CharacterSet.letters.contains) ? core : nil
        }
    }

    static func rebuild(_ parts: [Part], translations: [String]) -> String {
        var remaining = translations[...]
        return parts.map { part in
            switch part {
            case let .token(token):
                return token
            case let .text(text):
                let trimmed = Trimmed(text)
                guard trimmed.core.unicodeScalars.contains(where: CharacterSet.letters.contains),
                      let translated = remaining.popFirst()
                else { return text }
                return trimmed.leading + translated + trimmed.trailing
            }
        }.joined()
    }

    static func requests(body: String, warning: String?) -> [String] {
        requests(parts(body)) + (warning.map { [$0] } ?? [])
    }

    static func apply(_ translations: [String], body: String, warning: String?) -> (body: String, warning: String?) {
        let bodyParts = parts(body)
        let count = requests(bodyParts).count
        guard translations.count == count + (warning == nil ? 0 : 1) else { return (body, warning) }
        return (
            rebuild(bodyParts, translations: Array(translations.prefix(count))),
            warning == nil ? nil : translations.last)
    }
}

private struct Trimmed {
    let leading: String
    let core: String
    let trailing: String

    init(_ text: String) {
        let start = text.firstIndex { !$0.isWhitespace } ?? text.endIndex
        let end = text.lastIndex { !$0.isWhitespace }.map(text.index(after:)) ?? start
        leading = String(text[..<start])
        core = start < end ? String(text[start..<end]) : ""
        trailing = start < end ? String(text[end...]) : ""
    }
}

// MARK: 글

struct PostTranslationPlan {
    private enum Slot {
        case whole(blockIndex: Int, prefix: String)
        case lines(blockIndex: Int, lines: [Line])
        case jsonItems(blockIndex: Int, items: [(marker: String, translated: Bool)])
    }

    private struct Line {
        let prefix: String
        let cells: [String]?
        let translatable: Bool
    }

    let texts: [String]
    private let blocks: [PostBlock]
    private let slots: [Slot]

    init(title: String, blocks: [PostBlock]) {
        var texts = [title]
        var slots: [Slot] = []
        for (index, block) in blocks.enumerated() {
            let content = block.content ?? ""
            let next = index + 1 < blocks.count ? blocks[index + 1] : nil
            switch block.kind {
            case .paragraph:
                if BlockView.isThematicBreak(content) || InlineImageMarkdown.containsImage(content) { continue }
                if let sub = BlockView.subHeading(content) {
                    let text = Self.plain(sub.text)
                    guard Self.hasLetters(text) else { continue }
                    texts.append(text)
                    slots.append(.whole(blockIndex: index, prefix: String(repeating: "#", count: sub.level) + " "))
                } else if Self.hasLetters(content) {
                    texts.append(Self.plain(content))
                    slots.append(.whole(blockIndex: index, prefix: ""))
                }
            case .h1, .h2, .h3:
                guard Self.hasLetters(content) else { continue }
                texts.append(Self.plain(content))
                slots.append(.whole(blockIndex: index, prefix: ""))
            case .quote:
                if BlockView.isCalloutLabel(block, next: next) { continue }
                let lines = content.components(separatedBy: "\n")
                if let first = lines.first, BlockView.callout(in: content, body: nil) != nil {
                    let rest = lines.dropFirst().joined(separator: "\n")
                    guard Self.hasLetters(rest) else { continue }
                    texts.append(Self.plain(rest))
                    slots.append(.whole(blockIndex: index, prefix: first + "\n"))
                } else if Self.hasLetters(content) {
                    texts.append(Self.plain(content))
                    slots.append(.whole(blockIndex: index, prefix: ""))
                }
            case .listBullet, .listNumbered:
                if let data = content.data(using: .utf8), let items = try? JSONDecoder().decode([String].self, from: data) {
                    var markers: [(String, Bool)] = []
                    for item in items {
                        let (marker, text) = Self.splitListMarker(item, json: true)
                        let translatable = Self.hasLetters(text)
                        if translatable { texts.append(Self.plain(text)) }
                        markers.append((translatable ? marker : item, translatable))
                    }
                    slots.append(.jsonItems(blockIndex: index, items: markers))
                } else {
                    var lines: [Line] = []
                    for raw in content.components(separatedBy: "\n") {
                        let (prefix, text) = Self.splitListMarker(raw, json: false)
                        let translatable = Self.hasLetters(text)
                        if translatable { texts.append(Self.plain(text)) }
                        lines.append(Line(prefix: translatable ? prefix : raw, cells: nil, translatable: translatable))
                    }
                    slots.append(.lines(blockIndex: index, lines: lines))
                }
            case .table:
                var lines: [Line] = []
                for raw in content.components(separatedBy: "\n") {
                    let cells = Self.tableCells(raw)
                    guard let cells, !Self.isTableSeparator(raw) else {
                        lines.append(Line(prefix: raw, cells: nil, translatable: false))
                        continue
                    }
                    for cell in cells where Self.hasLetters(cell) { texts.append(cell) }
                    lines.append(Line(prefix: "", cells: cells, translatable: true))
                }
                slots.append(.lines(blockIndex: index, lines: lines))
            case .image, .ctaRef, .divider, .embed, .code, .unknown:
                continue
            }
        }
        self.texts = texts
        self.blocks = blocks
        self.slots = slots
    }

    func apply(_ translations: [String]) -> (title: String, blocks: [PostBlock])? {
        guard translations.count == texts.count, let title = translations.first else { return nil }
        var remaining = translations.dropFirst()
        var blocks = self.blocks
        for slot in slots {
            switch slot {
            case let .whole(index, prefix):
                guard let next = remaining.popFirst() else { return nil }
                blocks[index] = blocks[index].withContent(prefix + Self.escaped(next))
            case let .jsonItems(index, items):
                var out: [String] = []
                for item in items {
                    if item.translated {
                        guard let next = remaining.popFirst() else { return nil }
                        out.append(item.marker + Self.escaped(next))
                    } else {
                        out.append(item.marker)
                    }
                }
                let json = (try? JSONEncoder().encode(out)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                blocks[index] = blocks[index].withContent(json)
            case let .lines(index, lines):
                var out: [String] = []
                for line in lines {
                    if let cells = line.cells {
                        var row: [String] = []
                        for cell in cells {
                            if Self.hasLetters(cell) {
                                guard let next = remaining.popFirst() else { return nil }
                                row.append(Self.tableCell(next))
                            } else {
                                row.append(cell)
                            }
                        }
                        out.append("| " + row.joined(separator: " | ") + " |")
                    } else if line.translatable {
                        guard let next = remaining.popFirst() else { return nil }
                        out.append(line.prefix + Self.escaped(next))
                    } else {
                        out.append(line.prefix)
                    }
                }
                blocks[index] = blocks[index].withContent(out.joined(separator: "\n"))
            }
        }
        return (title, blocks)
    }

    static func plain(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: markdown, options: options) else { return markdown }
        return String(attributed.characters)
    }

    static func escaped(_ text: String) -> String {
        let specials: Set<Character> = ["\\", "*", "_", "`", "[", "]", "~"]
        return String(text.flatMap { specials.contains($0) ? ["\\", $0] : [$0] })
    }

    /// 표 셀은 마크다운 없이 그대로 그려지고 `|` 로만 갈린다 — 번역문의 `|` 는 전각으로.
    static func tableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "｜").replacingOccurrences(of: "\n", with: " ")
    }

    private static func hasLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: CharacterSet.letters.contains)
    }

    private static let listMarker = try? NSRegularExpression(pattern: #"^(\s*(?:[-*+]\s+|\d+[.)]\s+)?(?:\[[ xX]\]\s+)?)"#)
    private static let taskMarker = try? NSRegularExpression(pattern: #"^(\[[ xX]\]\s+)"#)

    private static func splitListMarker(_ line: String, json: Bool) -> (marker: String, text: String) {
        let pattern = json ? taskMarker : listMarker
        let ns = line as NSString
        let length = pattern?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
        return (ns.substring(to: length), ns.substring(from: length))
    }

    private static func tableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") || trimmed.contains("|") else { return nil }
        var body = Substring(trimmed)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.range(of: #"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#, options: .regularExpression) != nil
    }
}

// MARK: 번역기 — 목 모드는 가짜(시뮬레이터·테스트엔 실제 번역 모델이 없다)

protocol ContentTranslator {
    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String]
}

struct EchoTranslator: ContentTranslator {
    var fails = false

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        try await Task.sleep(for: .milliseconds(250))
        if fails { throw CancellationError() }
        let tag = target.languageCode?.identifier ?? "?"
        return texts.map { "[\(tag)] \($0)" }
    }
}

struct SessionTranslator: ContentTranslator {
    let session: TranslationSession

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
        var out = texts
        for response in try await session.translations(from: requests) {
            if let id = response.clientIdentifier.flatMap(Int.init), out.indices.contains(id) {
                out[id] = response.targetText
            }
        }
        return out
    }
}

// MARK: 세션 동안의 번역 기억

struct TranslationRequest: Equatable {
    let key: String
    let source: Locale.Language
    let target: Locale.Language
    let texts: [String]
}

@MainActor
@Observable
final class ContentTranslations {
    static let shared = ContentTranslations()

    enum Phase { case translating, shown }

    private(set) var phases: [String: Phase] = [:]
    private var results: [String: [String]] = [:]
    private var availability: [String: Bool] = [:]

    private init() {}

    func isAvailable(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        let pair = "\(source.minimalIdentifier)>\(target.minimalIdentifier)"
        if let known = availability[pair] { return known }
        let available = Config.useMocks
            ? true
            : await LanguageAvailability().status(from: source, to: target) != .unsupported
        availability[pair] = available
        return available
    }

    func shown(_ key: String) -> [String]? {
        phases[key] == .shown ? results[key] : nil
    }

    func showCached(_ key: String) -> Bool {
        guard results[key] != nil else { return false }
        phases[key] = .shown
        announce(String(localized: "번역문을 보여 줘요"))
        return true
    }

    func begin(_ key: String) {
        phases[key] = .translating
    }

    func finish(_ key: String, _ translations: [String]?, expected: Int) {
        guard let translations, translations.count == expected else {
            phases[key] = nil
            ToastCenter.shared.show(String(localized: "번역하지 못했어요"))
            return
        }
        results[key] = translations
        phases[key] = .shown
        announce(String(localized: "번역문을 보여 줘요"))
    }

    func showOriginal(_ key: String) {
        phases[key] = nil
        announce(String(localized: "원문을 보여 줘요"))
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

private struct TranslationRunner: ViewModifier {
    @Binding var request: TranslationRequest?
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        if Config.useMocks {
            content.task(id: request) {
                guard let request else { return }
                let translations = try? await EchoTranslator(fails: Config.translationFails)
                    .translate(request.texts, from: request.source, to: request.target)
                ContentTranslations.shared.finish(request.key, translations, expected: request.texts.count)
                self.request = nil
            }
        } else {
            content
                .onChange(of: request) { _, request in
                    guard let request else { return }
                    let next = TranslationSession.Configuration(source: request.source, target: request.target)
                    if configuration == next {
                        configuration?.invalidate()
                    } else {
                        configuration = next
                    }
                }
                .translationTask(configuration) { session in
                    guard let request else { return }
                    let translations = try? await SessionTranslator(session: session)
                        .translate(request.texts, from: request.source, to: request.target)
                    ContentTranslations.shared.finish(request.key, translations, expected: request.texts.count)
                    self.request = nil
                }
        }
    }
}

extension View {
    func translationRunner(_ request: Binding<TranslationRequest?>) -> some View {
        modifier(TranslationRunner(request: request))
    }
}
