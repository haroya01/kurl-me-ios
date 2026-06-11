//
//  FeedCard.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// 글 카드 = 목록 행 (§10.2). 카드 그리드 ❌ — 타이포 위계가 전부.
/// 조회수는 카드에서 제거. 좋아요는 >0 일 때만 강등 표시. 썸네일은 이미지 있을 때만.
struct FeedRow: View {
    let item: FeedItem
    var featured = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if featured {
                    Text("오늘의 글")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.link)
                }
                if let tag = item.tags.first {
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
                Text(item.title)
                    .font(.system(size: featured ? 22 : 18, weight: featured ? .bold : .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(featured ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let excerpt = item.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                MetaRow(author: item.author.username, date: item.publishedAt, likes: item.likeCount)
                    .padding(.top, 2)
            }

            if let urlString = item.ogImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Palette.hairline)
                }
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

/// 작가 컨텍스트가 고정된 행 (작가 블로그 / 시리즈 내부).
struct PostRow: View {
    let item: PostListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.accent)
                }
                if let tag = item.tags.first {
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
            }
            Text(item.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MetaRow(author: nil, date: item.publishedAt, likes: item.likeCount)
                .padding(.top, 2)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

/// 작가 · 날짜 · (좋아요 >0) 한 줄 메타 — slate-500.
struct MetaRow: View {
    var author: String?
    var date: Date?
    var likes: Int64

    var body: some View {
        HStack(spacing: 7) {
            if let author {
                Text(author).fontWeight(.medium)
            }
            if let date {
                if author != nil { dot }
                Text(date.relativeShort)
            }
            if likes > 0 {
                dot
                Label("\(likes)", systemImage: "heart")
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.secondary)
    }

    private var dot: some View {
        Text("·").foregroundStyle(Palette.faint)
    }
}
