//
//  FeedCard.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// 전역 피드 카드 — 작가 정보 포함.
struct FeedCard: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverImage(urlString: item.ogImageUrl)

            HStack(spacing: 6) {
                AvatarView(author: item.author, size: 22)
                Text(item.author.username)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if let date = item.publishedAt {
                    Text("·").foregroundStyle(.tertiary)
                    Text(date.relativeShort)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(item.title)
                .font(.title3.weight(.bold))
                .lineLimit(2)

            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 14) {
                ForEach(item.tags.prefix(3), id: \.self) { TagChip(tag: $0) }
                Spacer()
                Label("\(item.likeCount)", systemImage: "heart")
                Label("\(item.viewCount)", systemImage: "eye")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// 작가 블로그/시리즈 내 글 행 — 작가가 컨텍스트로 고정된 경우.
struct PostRow: View {
    let item: PostListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.brand)
                }
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                if let date = item.publishedAt {
                    Text(date.relativeShort)
                }
                Label("\(item.likeCount)", systemImage: "heart")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
