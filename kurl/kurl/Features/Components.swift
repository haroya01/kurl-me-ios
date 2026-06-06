//
//  Components.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

// MARK: 로딩/에러/빈 상태

enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

struct StateView<Value, Content: View>: View {
    let state: LoadState<Value>
    var retry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .tint(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 280)
        case .loaded(let value):
            content(value)
        case .failed(let message):
            ContentUnavailableView {
                Label(String(localized: "불러오지 못했습니다"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                if let retry {
                    Button(String(localized: "다시 시도"), action: retry)
                        .foregroundStyle(Palette.accent)
                }
            }
        }
    }
}

// MARK: 읽기 컬럼 (정중앙 max-w-2xl)

struct ReadingColumn<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: 섹션 라벨 — RailHeading (그린 마커 + 13px bold)

struct RailHeading: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.accentMarker)
                .frame(width: 3, height: 12)
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.heading)
        }
    }
}

// MARK: 1px hairline (slate-100)

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

// MARK: 그린 밑줄 탭 (active = 그린 한 가닥)

struct UnderlineTabs<T: Hashable & Identifiable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 22) {
            ForEach(items) { item in
                let active = item == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = item }
                } label: {
                    VStack(spacing: 7) {
                        Text(label(item))
                            .font(.system(size: 15, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Palette.ink : Palette.secondary)
                        ZStack {
                            Capsule().fill(.clear).frame(height: 2)
                            if active {
                                Capsule().fill(Palette.accent).frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: ns)
                            }
                        }
                    }
                    .fixedSize()
                    .animation(.snappy(duration: 0.2), value: active)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: 절제된 칩 (slate, 초록 캡슐 금지)

struct MutedChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.chipText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Palette.chipBg, in: Capsule())
    }
}

// MARK: 작가 아바타

struct AvatarView: View {
    let author: Author
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let urlString = author.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(Palette.chipBg)
            .overlay(
                Text(author.username.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            )
    }
}

// MARK: 상대 시간

extension Date {
    var relativeShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var mediumDate: String {
        formatted(.dateTime.year().month(.abbreviated).day())
    }
}
