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
            .padding(.horizontal, FeedHeaderMetrics.edge)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: unread.count > 0)
        .padding(.bottom, 8)
    }
}

extension FeedHeaderBar where Leading == EmptyView {
    init(items: [Item], selection: Binding<Item>, label: @escaping (Item) -> String) {
        self.init(items: items, selection: selection, label: label) { EmptyView() }
    }
}

/// 시스템 내비 바의 뒤로 버튼과 같은 크기·자리 — 푸시하면 같은 자리에서 뒤로 버튼으로 바뀐다.
enum FeedHeaderMetrics {
    static let circle: CGFloat = 44
    static let edge: CGFloat = 16
}

struct FeedHeaderGlyph: View {
    let systemImage: String
    var dot = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17))
            .imageScale(.large)
            .foregroundStyle(.primary)
            .overlay(alignment: .topTrailing) {
                if dot {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: FeedHeaderMetrics.circle, height: FeedHeaderMetrics.circle)
            .contentShape(Circle())
    }
}

/// 값 링크여야 인박스 안의 딥링크가 같은 스택에서 이어 밀린다(isPresented 목적지는 값 푸시마다 재발화).
struct InboxBell: View {
    let count: Int64

    var body: some View {
        NavigationLink(value: Route.notifications) {
            FeedHeaderGlyph(systemImage: "bell", dot: count > 0)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("알림"))
        .accessibilityValue(count > 0 ? Text("읽지 않음 \(count)") : Text(""))
    }
}
