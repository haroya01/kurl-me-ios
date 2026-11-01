import CoreText
import SwiftUI
import UIKit

extension NoteText {
    enum Inline: Equatable {
        case text(AttributedString)
        case emoji(String)
    }

    static let zeroWidthSpace: Unicode.Scalar = "\u{200B}"

    static func inlines(_ text: AttributedString, emojis: Set<String>) -> [Inline] {
        var result: [Inline] = []
        func add(_ piece: AttributedString) {
            guard !piece.characters.isEmpty else { return }
            if case let .text(previous)? = result.last {
                result[result.count - 1] = .text(previous + piece)
            } else {
                result.append(.text(piece))
            }
        }
        for run in text.runs {
            let slice = AttributedString(text[run.range])
            guard run.link == nil, !emojis.isEmpty else {
                add(slice)
                continue
            }
            let scalars = Array(String(slice.characters).unicodeScalars)
            var buffer = String.UnicodeScalarView()
            var index = 0
            while index < scalars.count {
                if let code = shortcode(in: scalars, at: index), emojis.contains(code) {
                    while buffer.last == zeroWidthSpace { buffer.removeLast() }
                    add(AttributedString(String(buffer), attributes: run.attributes))
                    buffer = String.UnicodeScalarView()
                    result.append(.emoji(code))
                    index += code.unicodeScalars.count + 2
                    while index < scalars.count, scalars[index] == zeroWidthSpace { index += 1 }
                    continue
                }
                buffer.append(scalars[index])
                index += 1
            }
            add(AttributedString(String(buffer), attributes: run.attributes))
        }
        return result
    }

    private static func shortcode(in scalars: [Unicode.Scalar], at start: Int) -> String? {
        guard scalars[start] == ":" else { return nil }
        var end = start + 1
        while end < scalars.count, CustomEmoji.isShortcodeScalar(scalars[end]) { end += 1 }
        guard end < scalars.count, scalars[end] == ":", end - start > 2 else { return nil }
        return String(String.UnicodeScalarView(scalars[(start + 1)..<end]))
    }
}

struct EmojiText: View {
    static let loadPoints: CGFloat = 20

    private let plain: Text
    private let inlines: [NoteText.Inline]
    private let urls: [String: URL]

    @Environment(\.font) private var font
    @Environment(\.fontResolutionContext) private var fontContext
    @State private var slots: [URL: Slot]
    @State private var loaded: [URL: CGImage] = [:]

    enum Slot: Equatable {
        case sized(CGFloat)
        case square
        case text
    }

    init(_ text: AttributedString, emojis: [CustomEmoji]?) {
        self.init(plain: Text(text), text: text, emojis: emojis)
    }

    init(verbatim text: String, emojis: [CustomEmoji]?) {
        self.init(plain: Text(verbatim: text), text: AttributedString(text), emojis: emojis)
    }

    private init(plain: Text, text: AttributedString, emojis: [CustomEmoji]?) {
        self.plain = plain
        let table = CustomEmoji.table(emojis)
        let inlines = table.isEmpty ? [] : NoteText.inlines(text, emojis: Set(table.keys))
        let codes = Set(inlines.compactMap { if case let .emoji(code) = $0 { code } else { nil } })
        self.inlines = codes.isEmpty ? [] : inlines
        urls = table.filter { codes.contains($0.key) }
        _slots = State(initialValue: Dictionary(uniqueKeysWithValues: Set(urls.values).map { ($0, Self.slot(for: $0)) }))
    }

    static func slot(for url: URL, in cache: RemoteImageCache = .shared) -> Slot {
        if let image = cache.cached(url, maxPixel: loadPoints).flatMap(still) {
            return .sized(CGFloat(image.width) / CGFloat(image.height))
        }
        return cache.hasFailed(url) ? .text : .square
    }

    nonisolated private static func still(_ image: UIImage) -> CGImage? {
        guard let still = (image.images?.first ?? image).cgImage, still.width > 0, still.height > 0 else { return nil }
        return still
    }

    var body: some View {
        if inlines.isEmpty {
            plain
        } else {
            composed(height: CTFontGetAscent((font ?? .body).resolve(in: fontContext).ctFont))
                .task(id: Set(urls.values)) { await load() }
        }
    }

    private func composed(height: CGFloat) -> Text {
        var line = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: inlines.count)
        for inline in inlines {
            switch inline {
            case let .text(text): line.appendInterpolation(Text(text))
            case let .emoji(code): line.appendInterpolation(glyph(code, height: height))
            }
        }
        return Text(LocalizedStringKey(stringInterpolation: line))
    }

    private func glyph(_ code: String, height: CGFloat) -> Text {
        let name = ":\(code):"
        guard let url = urls[code], let slot = slots[url] else { return Text(verbatim: name) }
        let ratio: CGFloat
        switch slot {
        case .text: return Text(verbatim: name)
        case let .sized(value): ratio = value
        case .square: ratio = 1
        }
        let image = loaded[url] ?? RemoteImageCache.shared.cached(url, maxPixel: Self.loadPoints).flatMap(Self.still)
        let size = CGSize(width: height * ratio, height: height)
        return Text(Self.picture(image, in: size, label: Text(verbatim: name)))
    }

    private static func picture(_ image: CGImage?, in size: CGSize, label: Text) -> Image {
        guard let image else { return Image(size: size, label: label) { _ in } }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        if abs(size.height * width / height - size.width) < 0.5 {
            return Image(image, scale: height / size.height, label: label)
                .renderingMode(.original)
                .interpolation(.high)
        }
        let scale = min(size.width / width, size.height / height)
        let fitted = CGRect(
            x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2,
            width: width * scale, height: height * scale)
        return Image(size: size, label: label) { context in
            context.draw(Image(decorative: image, scale: 1).interpolation(.high), in: fitted)
        }
    }

    private func load() async {
        let missing = Set(urls.values).filter { url in
            slots[url] != .text && loaded[url] == nil
                && RemoteImageCache.shared.cached(url, maxPixel: Self.loadPoints) == nil
        }
        guard !missing.isEmpty else { return }
        let points = Self.loadPoints
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in missing {
                group.addTask { (url, await RemoteImageCache.shared.load(url, maxPixel: points)) }
            }
            for await (url, image) in group {
                guard !Task.isCancelled else { return }
                if let still = image.flatMap(Self.still) { loaded[url] = still }
            }
        }
    }
}
