//
//  FeedHeaderBar.swift
//  kurl
//

import SwiftUI

struct FeedHeaderBar<Item: Hashable & Identifiable, Leading: View>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    @ViewBuilder var leading: Leading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var unread = UnreadStore.shared

    var body: some View {
        let signedIn = AuthStore.shared.isSignedIn
        GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
            HStack(spacing: 0) {
                if signedIn {
                    ZStack { leading }
                        .frame(width: FeedHeaderMetrics.circle, height: FeedHeaderMetrics.circle)
                }
                Spacer(minLength: 0)
                GlassSegmentSwitcher(items: items, selection: $selection, label: label)
                Spacer(minLength: 0)
                if signedIn {
                    InboxBell(count: unread.count)
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: unread.count > 0)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

extension FeedHeaderBar where Leading == EmptyView {
    init(items: [Item], selection: Binding<Item>, label: @escaping (Item) -> String) {
        self.init(items: items, selection: selection, label: label) { EmptyView() }
    }
}

enum FeedHeaderMetrics {
    static let circle: CGFloat = 40
}

struct FeedHeaderGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: FeedHeaderMetrics.circle, height: FeedHeaderMetrics.circle)
            .contentShape(Circle())
    }
}

/// 값 링크여야 인박스 안의 딥링크가 같은 스택에서 이어 밀린다(isPresented 목적지는 값 푸시마다 재발화).
struct InboxBell: View {
    let count: Int64

    var body: some View {
        NavigationLink(value: Route.notifications) {
            FeedHeaderGlyph(systemImage: "bell")
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: -7, y: 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("알림"))
        .accessibilityValue(count > 0 ? Text("읽지 않음 \(count)") : Text(""))
    }
}
