import SwiftUI

struct FeedPlaceholder: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var actionIdentifier: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .typeScale(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .expandTapTarget(12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(actionIdentifier ?? "", isEnabled: actionIdentifier != nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 행 전체 press 하이라이트 — 본문 정렬 유지(양옆으로 살짝 번짐).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(configuration.isPressed ? Palette.rowHighlight : .clear)
                    .padding(.horizontal, -10)
            )
            .contentShape(Rectangle())
            .animation(Motion.micro, value: configuration.isPressed)
    }
}

struct FeedSkeleton: View {
    var count = 5

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    SkeletonRow(index: i)
                        .rowDivider(i > 0)
                }
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityLabel(Text("불러오는 중"))
    }
}

struct NoteSkeleton: View {
    var count = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Palette.hairlineStrong).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 9) {
                        SkeletonBar(widthFraction: 0.34, height: 13)
                        SkeletonBar(widthFraction: 0.96, height: 14)
                        SkeletonBar(widthFraction: i.isMultiple(of: 2) ? 0.62 : 0.8, height: 14)
                        SkeletonBar(widthFraction: 0.5, height: 12).padding(.top, 4)
                    }
                }
                .padding(.vertical, 14)
                if i < count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
            }
        }
        .modifier(SkeletonShimmer())
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Text("불러오는 중"))
    }
}

private struct SkeletonBar: View {
    let widthFraction: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Palette.hairlineStrong)
                .frame(width: geo.size.width * widthFraction, height: height)
        }
        .frame(height: height)
    }
}

private struct SkeletonRow: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBar(widthFraction: 0.3, height: 12)
            SkeletonBar(widthFraction: 0.92, height: 18)
            SkeletonBar(widthFraction: index.isMultiple(of: 2) ? 0.6 : 0.74, height: 18)
            SkeletonBar(widthFraction: 0.96, height: 14).padding(.top, 2)
            HStack(spacing: 6) {
                Circle().fill(Palette.hairlineStrong).frame(width: 16, height: 16)
                SkeletonBar(widthFraction: 0.32, height: 12)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 16)
        .modifier(SkeletonShimmer())
    }
}

extension EnvironmentValues {
    @Entry var skeletonAnimates = true
}

private struct SkeletonShimmer: ViewModifier {
    @Environment(\.skeletonAnimates) private var animates

    func body(content: Content) -> some View {
        if animates {
            content.modifier(SkeletonSweep())
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
    }
}

/// 절제된 shimmer — 옅은 빛 띠가 카드를 한 번씩 느리게 쓸고 지나간다. Reduce Motion 이면 정지.
private struct SkeletonSweep: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.45), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.55)
                            .offset(x: travel ? w * 1.1 : -w * 0.65)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    travel = true
                }
            }
    }
}
