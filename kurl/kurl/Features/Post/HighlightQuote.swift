import SwiftUI
import UIKit

struct HighlightQuote: View {
    let quote: String
    let mine: Bool
    let hasThread: Bool

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = false

    static let sweepDelay: Duration = .milliseconds(250)
    static let sweep = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.44)

    private var progress: CGFloat { reduceMotion || swept ? 1 : 0 }

    var body: some View {
        HighlightQuoteText(quote: quote, size: size, paint: nil)
            .background {
                HighlightQuoteText(quote: quote, size: size, paint: .init(mine: mine, hasThread: hasThread))
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: progress, y: 1, anchor: .leading)
                    }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: quote))
            .accessibilityIdentifier("highlight.quote")
            .task {
                guard !reduceMotion, !swept else { return }
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
    let paint: Paint?

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: false)
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

    func updateUIView(_ tv: UITextView, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = size * 0.68
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
        if tv.attributedText != text { tv.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? (uiView.bounds.width > 0 ? uiView.bounds.width : 320)
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }
}
