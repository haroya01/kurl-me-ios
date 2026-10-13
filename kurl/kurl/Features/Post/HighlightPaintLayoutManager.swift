import UIKit

final class HighlightPaintLayoutManager: NSLayoutManager {
    private var origin: CGPoint = .zero

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        self.origin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<CGRect>, count rectCount: Int,
        forCharacterRange charRange: NSRange, color: UIColor
    ) {
        // NSLayoutManager 는 연달아 꽉 찬 줄들을 사각형 하나로 합쳐 넘긴다.
        let bands = (0..<rectCount).flatMap { bands(in: rectArray[$0], for: charRange) }
        bands.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            super.fillBackgroundRectArray(base, count: buffer.count, forCharacterRange: charRange, color: color)
        }
    }

    override func drawUnderline(
        forGlyphRange glyphRange: NSRange, underlineType underlineVal: NSUnderlineStyle,
        baselineOffset: CGFloat, lineFragmentRect lineRect: CGRect,
        lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: CGPoint
    ) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }
        let color = storage.attribute(.underlineColor, at: charRange.location, effectiveRange: nil) as? UIColor
            ?? storage.attribute(.foregroundColor, at: charRange.location, effectiveRange: nil) as? UIColor
            ?? .label
        let bottom = lineRect.minY + glyphBoxHeight(ofLine: lineGlyphRange, storage: storage)
        let thickness: CGFloat = underlineVal.contains(.thick) ? 2 : 1
        let span = boundingRect(forGlyphRange: glyphRange, in: container)
        color.setFill()
        UIRectFillUsingBlendMode(
            CGRect(
                x: span.minX + containerOrigin.x, y: bottom - thickness + containerOrigin.y,
                width: span.width, height: thickness),
            .normal)
    }

    private func bands(in rect: CGRect, for charRange: NSRange) -> [CGRect] {
        guard let storage = textStorage, numberOfGlyphs > 0 else { return [rect] }
        let top = rect.minY - origin.y
        let bottom = rect.maxY - origin.y
        var bands: [CGRect] = []
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
            guard min(line.maxY, bottom) - max(line.minY, top) > 1 else { return }
            let height = min(line.height, self.glyphBoxHeight(ofLine: lineGlyphs, storage: storage))
            bands.append(CGRect(x: rect.minX, y: line.minY + self.origin.y, width: rect.width, height: height))
        }
        return bands.isEmpty ? [rect] : bands
    }

    private func glyphBoxHeight(ofLine lineGlyphs: NSRange, storage: NSTextStorage) -> CGFloat {
        let chars = characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
        return location(forGlyphAt: lineGlyphs.location).y + maxDescent(in: chars, storage: storage)
    }

    private func maxDescent(in range: NSRange, storage: NSTextStorage) -> CGFloat {
        var descent: CGFloat = 0
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? UIFont { descent = max(descent, -font.descender) }
        }
        return descent
    }
}
