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
        let bands = (0..<rectCount).map { index -> CGRect in
            let rect = rectArray[index]
            guard let band = band(at: CGPoint(x: rect.midX - origin.x, y: rect.midY - origin.y), in: charRange)
            else { return rect }
            return CGRect(x: rect.minX, y: band.minY + origin.y, width: rect.width, height: band.height)
        }
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

    private func band(at point: CGPoint, in charRange: NSRange) -> CGRect? {
        guard let storage = textStorage, let container = textContainers.first, numberOfGlyphs > 0 else { return nil }
        let glyph = glyphIndex(for: point, in: container)
        var lineGlyphs = NSRange()
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
        let lineChars = characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
        guard NSIntersectionRange(lineChars, charRange).length > 0 else { return nil }
        let height = min(line.height, glyphBoxHeight(ofLine: lineGlyphs, storage: storage))
        return CGRect(x: line.minX, y: line.minY, width: line.width, height: height)
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
