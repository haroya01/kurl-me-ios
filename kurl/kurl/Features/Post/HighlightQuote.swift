import SwiftUI
import UIKit

struct HighlightQuote: View {
    let quote: String
    let mine: Bool
    let hasThread: Bool
    let sweeps: Bool
    let lineSpacing: CGFloat
    let maxLines: Int
    let identifier: String

    @ScaledMetric private var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = false

    static let sweepDelay: Duration = .milliseconds(250)
    static let sweep = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.44)

    init(
        quote: String, mine: Bool, hasThread: Bool, sweeps: Bool = true,
        size: CGFloat = 18, relativeTo textStyle: Font.TextStyle = .body, lineSpacing: CGFloat = 0.68,
        maxLines: Int = 0, identifier: String = "highlight.quote"
    ) {
        self.quote = quote
        self.mine = mine
        self.hasThread = hasThread
        self.sweeps = sweeps
        self.lineSpacing = lineSpacing
        self.maxLines = maxLines
        self.identifier = identifier
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    private var progress: CGFloat { !sweeps || reduceMotion || swept ? 1 : 0 }

    var body: some View {
        HighlightQuoteText(quote: quote, size: size, lineSpacing: lineSpacing, maxLines: maxLines, paint: nil)
            .background {
                HighlightQuoteText(
                    quote: quote, size: size, lineSpacing: lineSpacing, maxLines: maxLines,
                    paint: .init(mine: mine, hasThread: hasThread))
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: progress, y: 1, anchor: .leading)
                    }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: quote))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(identifier)
            .task {
                guard sweeps, !reduceMotion, !swept else { return }
                try? await Task.sleep(for: Self.sweepDelay)
                guard !Task.isCancelled else { return }
                withAnimation(Self.sweep) { swept = true }
            }
    }
}

private struct HighlightQuoteText: UIViewRepresentable {
    struct Paint: Equatable {
        let mine: Bool
        let hasThread: Bool
    }

    let quote: String
    let size: CGFloat
    let lineSpacing: CGFloat
    let maxLines: Int
    let paint: Paint?

    func makeUIView(context: Context) -> ProseTextView {
        let tv = ProseTextView(usingTextLayoutManager: false)
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.isUserInteractionEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        tv.isAccessibilityElement = false
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: ProseTextView, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = size * lineSpacing
        let text = NSMutableAttributedString(string: quote, attributes: [
            .font: UIFont.systemFont(ofSize: size),
            .foregroundColor: paint == nil ? UIColor(Palette.ink) : UIColor.clear,
            .paragraphStyle: paragraph,
        ])
        if let paint {
            SelectableProseText.paint(
                text, range: NSRange(location: 0, length: text.length),
                mine: paint.mine, hasThread: paint.hasThread)
        }
        tv.textContainer.maximumNumberOfLines = maxLines
        tv.textContainer.lineBreakMode = .byTruncatingTail
        if tv.attributedText != text { tv.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProseTextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? (uiView.bounds.width > 0 ? uiView.bounds.width : 320)
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }
}
