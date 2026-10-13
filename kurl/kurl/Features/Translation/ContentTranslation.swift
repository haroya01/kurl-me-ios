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
    static let appLanguages = ["ko", "en", "ja", "vi", "hi"]

    static func source(declared: String?, text: String, preferred: [String] = Locale.preferredLanguages) -> Locale.Language? {
        guard let language = language(declared: declared, text: text),
              language.languageCode?.identifier != preferred.first.flatMap(languageCode)
        else { return nil }
        return language
    }

    static func language(declared: String?, text: String) -> Locale.Language? {
        (declared.flatMap { languageCode($0) } ?? detect(text)).map { Locale.Language(identifier: $0) }
    }

    static func choices(for source: Locale.Language) -> [Locale.Language] {
        appLanguages.filter { $0 != source.languageCode?.identifier }.map { Locale.Language(identifier: $0) }
    }

    static func nativeName(_ language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? ""
        return Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
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

struct PostTranslationOffer: Equatable {
    struct Choice: Equatable {
        let target: Locale.Language
        let available: Bool
    }

    let source: Locale.Language
    let direct: Locale.Language?
    let choices: [Choice]

    static func make(
        language: Locale.Language,
        preferred: [String] = Locale.preferredLanguages,
        available: (Locale.Language) async -> Bool
    ) async -> PostTranslationOffer? {
        let device = TranslationGate.target(preferred: preferred)
        if language.languageCode != device.languageCode, await available(device) {
            return PostTranslationOffer(source: language, direct: device, choices: [])
        }
        var choices: [Choice] = []
        for target in TranslationGate.choices(for: language) {
            choices.append(Choice(target: target, available: await available(target)))
        }
        guard choices.contains(where: \.available) else { return nil }
        return PostTranslationOffer(source: language, direct: nil, choices: choices)
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
    struct Applied {
        let title: String
        let blocks: [PostBlock]
        let titleTranslated: Bool
        let translatedBlocks: Set<Int>
    }

    private enum Slot {
        case whole(blockIndex: Int, prefix: String)
        case lines(blockIndex: Int, lines: [Line])
        case jsonItems(blockIndex: Int, items: [(marker: String, translated: Bool)])

        var blockIndex: Int {
            switch self {
            case let .whole(index, _), let .lines(index, _), let .jsonItems(index, _): index
            }
        }
    }

    private struct Line {
        let prefix: String
        let cells: [String]?
        let translatable: Bool
    }

    let texts: [String]
    private let title: String
    private let blocks: [PostBlock]
    private let slots: [(slot: Slot, segments: Range<Int>)]

    init(title: String, blocks: [PostBlock]) {
        var texts = [title]
        var slots: [(slot: Slot, segments: Range<Int>)] = []
        for (index, block) in blocks.enumerated() {
            let content = block.content ?? ""
            let next = index + 1 < blocks.count ? blocks[index + 1] : nil
            let start = texts.count
            var slot: Slot?
            switch block.kind {
            case .paragraph:
                if BlockView.isThematicBreak(content) || InlineImageMarkdown.containsImage(content) { continue }
                if let sub = BlockView.subHeading(content) {
                    let text = Self.plain(sub.text)
                    guard Self.hasLetters(text) else { continue }
                    texts.append(text)
                    slot = .whole(blockIndex: index, prefix: String(repeating: "#", count: sub.level) + " ")
                } else if Self.hasLetters(content) {
                    texts.append(Self.plain(content))
                    slot = .whole(blockIndex: index, prefix: "")
                }
            case .h1, .h2, .h3:
                guard Self.hasLetters(content) else { continue }
                texts.append(Self.plain(content))
                slot = .whole(blockIndex: index, prefix: "")
            case .quote:
                if BlockView.isCalloutLabel(block, next: next) { continue }
                let lines = content.components(separatedBy: "\n")
                if let first = lines.first, BlockView.callout(in: content, body: nil) != nil {
                    let rest = lines.dropFirst().joined(separator: "\n")
                    guard Self.hasLetters(rest) else { continue }
                    texts.append(Self.plain(rest))
                    slot = .whole(blockIndex: index, prefix: first + "\n")
                } else if Self.hasLetters(content) {
                    texts.append(Self.plain(content))
                    slot = .whole(blockIndex: index, prefix: "")
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
                    slot = .jsonItems(blockIndex: index, items: markers)
                } else {
                    var lines: [Line] = []
                    for raw in content.components(separatedBy: "\n") {
                        let (prefix, text) = Self.splitListMarker(raw, json: false)
                        let translatable = Self.hasLetters(text)
                        if translatable { texts.append(Self.plain(text)) }
                        lines.append(Line(prefix: translatable ? prefix : raw, cells: nil, translatable: translatable))
                    }
                    slot = .lines(blockIndex: index, lines: lines)
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
                slot = .lines(blockIndex: index, lines: lines)
            case .image, .ctaRef, .divider, .embed, .code, .unknown:
                continue
            }
            if let slot, texts.count > start {
                slots.append((slot, start..<texts.count))
            }
        }
        self.texts = texts
        self.title = title
        self.blocks = blocks
        self.slots = slots
    }

    func apply(_ translations: [String]) -> (title: String, blocks: [PostBlock])? {
        apply(partial: translations).map { ($0.title, $0.blocks) }
    }

    func apply(partial translations: [String?]) -> Applied? {
        guard translations.count == texts.count else { return nil }
        var blocks = self.blocks
        var translatedBlocks: Set<Int> = []
        for (slot, segments) in slots {
            let arrived = translations[segments].compactMap { $0 }
            guard arrived.count == segments.count else { continue }
            var remaining = arrived[...]
            let index = slot.blockIndex
            blocks[index] = blocks[index].withContent(Self.content(slot, &remaining))
            translatedBlocks.insert(index)
        }
        let title = translations.first ?? nil
        return Applied(
            title: title ?? self.title, blocks: blocks,
            titleTranslated: title != nil, translatedBlocks: translatedBlocks)
    }

    private static func content(_ slot: Slot, _ remaining: inout ArraySlice<String>) -> String {
        switch slot {
        case let .whole(_, prefix):
            return prefix + escaped(remaining.popFirst() ?? "")
        case let .jsonItems(_, items):
            let out = items.map { item in
                item.translated ? item.marker + escaped(remaining.popFirst() ?? "") : item.marker
            }
            return (try? JSONEncoder().encode(out)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        case let .lines(_, lines):
            return lines.map { line in
                if let cells = line.cells {
                    let row = cells.map { hasLetters($0) ? tableCell(remaining.popFirst() ?? $0) : $0 }
                    return "| " + row.joined(separator: " | ") + " |"
                }
                return line.translatable ? line.prefix + escaped(remaining.popFirst() ?? "") : line.prefix
            }.joined(separator: "\n")
        }
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
    /// `received` 가 false 를 돌려주면 남은 요청을 버리고 끝낸다.
    func translate(
        _ texts: [String], from source: Locale.Language, to target: Locale.Language,
        received: (_ index: Int, _ text: String) -> Bool
    ) async throws
}

struct EchoTranslator: ContentTranslator {
    struct Failure: Error {}

    var fails = false
    var delay: Duration = .milliseconds(150)

    func translate(
        _ texts: [String], from source: Locale.Language, to target: Locale.Language,
        received: (_ index: Int, _ text: String) -> Bool
    ) async throws {
        let tag = target.languageCode?.identifier ?? "?"
        for (index, text) in texts.enumerated() {
            try await Task.sleep(for: delay)
            if fails, index >= texts.count / 2 { throw Failure() }
            guard received(index, "[\(tag)] \(text)") else { return }
        }
    }
}

struct SessionTranslator: ContentTranslator {
    let session: TranslationSession

    func translate(
        _ texts: [String], from source: Locale.Language, to target: Locale.Language,
        received: (_ index: Int, _ text: String) -> Bool
    ) async throws {
        let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
        for try await response in session.translate(batch: requests) {
            guard let id = response.clientIdentifier.flatMap(Int.init), texts.indices.contains(id) else { continue }
            guard received(id, response.targetText) else {
                session.cancel()
                return
            }
        }
    }
}

// MARK: 세션 동안의 번역 기억

struct TranslationRequest: Equatable {
    let id = UUID()
    let key: String
    let source: Locale.Language
    let target: Locale.Language
    let texts: [String]
}

struct TranslationProgress: Equatable {
    let done: Int
    let total: Int
}

@MainActor
@Observable
final class ContentTranslations {
    static let shared = ContentTranslations()

    enum Phase { case translating, shown }

    private(set) var phases: [String: Phase] = [:]
    private var partials: [String: [String?]] = [:]
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

    func partial(_ key: String) -> [String?]? {
        phases[key] == .translating ? partials[key] : nil
    }

    func progress(_ key: String) -> TranslationProgress? {
        partial(key).map { TranslationProgress(done: $0.count { $0 != nil }, total: $0.count) }
    }

    func showCached(_ key: String) -> Bool {
        guard results[key] != nil else { return false }
        phases[key] = .shown
        announce(String(localized: "번역문을 보여 줘요"))
        return true
    }

    func begin(_ request: TranslationRequest) {
        phases[request.key] = .translating
        partials[request.key] = Array(repeating: nil, count: request.texts.count)
    }

    func receive(_ key: String, index: Int, text: String) {
        guard phases[key] == .translating, var partial = partials[key],
              partial.indices.contains(index), partial[index] == nil
        else { return }
        partial[index] = text
        partials[key] = partial
    }

    func finish(_ key: String, _ translations: [String]?, expected: Int) {
        partials[key] = nil
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
        partials[key] = nil
        phases[key] = nil
        announce(String(localized: "원문을 보여 줘요"))
    }

    func run(_ request: TranslationRequest, with translator: some ContentTranslator, isCurrent: () -> Bool) async {
        let key = request.key
        func live() -> Bool { isCurrent() && phases[key] == .translating }
        do {
            try await translator.translate(request.texts, from: request.source, to: request.target) { index, text in
                guard live() else { return false }
                receive(key, index: index, text: text)
                return true
            }
        } catch {
            if live() { finish(key, nil, expected: request.texts.count) }
            return
        }
        guard live(), let partial = partials[key] else { return }
        finish(key, zip(partial, request.texts).map { $0 ?? $1 }, expected: request.texts.count)
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
                await run(request, with: EchoTranslator(fails: Config.translationFails, delay: Config.translationDelay))
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
                    await run(request, with: SessionTranslator(session: session))
                }
        }
    }

    private func run(_ request: TranslationRequest, with translator: some ContentTranslator) async {
        await ContentTranslations.shared.run(request, with: translator) { self.request == request }
        if self.request == request { self.request = nil }
    }
}

extension View {
    func translationRunner(_ request: Binding<TranslationRequest?>) -> some View {
        modifier(TranslationRunner(request: request))
    }
}
