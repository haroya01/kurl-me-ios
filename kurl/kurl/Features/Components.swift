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

/// 비동기 콘텐츠의 로딩/에러/빈 상태를 일관되게 처리한다.
struct StateView<Value, Content: View>: View {
    let state: LoadState<Value>
    var retry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
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
                        .buttonStyle(.borderedProminent)
                        .tint(.brand)
                }
            }
        }
    }
}

// MARK: 태그 칩

struct TagChip: View {
    let tag: String

    var body: some View {
        Text("#\(tag)")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Brand.green.opacity(0.10), in: Capsule())
            .foregroundStyle(.brand)
    }
}

// MARK: 커버 이미지

struct CoverImage: View {
    let urlString: String?
    var height: CGFloat = 180

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    Rectangle().fill(.quaternary).overlay(ProgressView())
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
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
            .fill(Brand.green.opacity(0.15))
            .overlay(
                Text(author.username.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.brand)
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
}
