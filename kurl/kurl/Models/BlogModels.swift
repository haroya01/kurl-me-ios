//
//  BlogModels.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation

// MARK: 작가

struct Author: Decodable, Hashable, Identifiable {
    let id: Int64
    let username: String
    let bio: String?
    let avatarUrl: String?
}

struct SuggestedAuthor: Decodable, Identifiable {
    let author: Author
    let postCount: Int

    var id: Int64 { author.id }
}

// MARK: 글

/// 전역 피드 카드. (/public/posts)
struct FeedItem: Decodable, Hashable, Identifiable {
    let id: Int64
    let author: Author
    let slug: String
    let title: String
    let excerpt: String?
    let ogImageUrl: String?
    let languageTag: String?
    let tags: [String]
    let publishedAt: Date?
    let viewCount: Int64
    let likeCount: Int64
}

struct PublicFeedView: Decodable {
    let items: [FeedItem]
    let page: Int
    let size: Int
    let hasNext: Bool
}

/// 작가 글 목록/상세 헤더 아이템.
struct PostListItem: Decodable, Hashable, Identifiable {
    let id: Int64
    let slug: String
    let title: String
    let excerpt: String?
    let ogImageUrl: String?
    let languageTag: String?
    let tags: [String]
    let likeCount: Int64
    let publishedAt: Date?
    let lastEditedAt: Date?
    let pinned: Bool
}

struct PublicPostListView: Decodable {
    let author: Author
    let posts: [PostListItem]
}

// MARK: 글 상세 + 블록

struct PublicPostDetail: Decodable {
    let author: Author
    let post: PostListItem
    let blocks: [PostBlock]
    let series: PostSeriesNav?
}

struct PostBlock: Decodable, Identifiable {
    let type: String
    let content: String?
    let blockOrder: Int?
    let cta: CtaInfo?

    var id: Int { blockOrder ?? UUID().hashValue }
    var kind: BlockKind { BlockKind(rawValue: type) ?? .unknown }
}

struct CtaInfo: Decodable, Hashable {
    let label: String
    let url: String
    let style: String?
    let purpose: String?
    let deleted: Bool
}

enum BlockKind: String {
    case paragraph = "PARAGRAPH"
    case h1 = "H1"
    case h2 = "H2"
    case h3 = "H3"
    case image = "IMAGE"
    case ctaRef = "CTA_REF"
    case divider = "DIVIDER"
    case quote = "QUOTE"
    case listBullet = "LIST_BULLET"
    case listNumbered = "LIST_NUMBERED"
    case embed = "EMBED"
    case code = "CODE"
    case table = "TABLE"
    case unknown
}

struct PostSeriesNav: Decodable, Hashable {
    let slug: String
    let title: String
    let position: Int
    let total: Int
    let prev: NavLink?
    let next: NavLink?

    struct NavLink: Decodable, Hashable {
        let slug: String
        let title: String
    }
}

// MARK: 시리즈

struct SeriesPostRef: Decodable, Hashable {
    let slug: String
    let title: String
}

struct PublicSeriesCard: Decodable, Identifiable {
    let id: Int64
    let author: Author?
    let slug: String
    let title: String
    let postCount: Int
    let lastPublishedAt: Date?
    let posts: [SeriesPostRef]
}

struct SeriesListItem: Decodable, Hashable, Identifiable {
    let id: Int64
    let slug: String
    let title: String
    let postCount: Int
    let tags: [String]
}

struct PublicSeriesListView: Decodable {
    let author: Author
    let series: [SeriesListItem]
}

struct PublicSeriesDetail: Decodable {
    let author: Author
    let series: SeriesListItem
    let posts: [PostListItem]
}

// MARK: 발견 / 태그 / 댓글

struct TagCount: Decodable, Identifiable {
    let tag: String
    let count: Int64

    var id: String { tag }
}

struct TrendingTagSection: Decodable, Identifiable {
    let tag: String
    let postCount: Int64
    let posts: [FeedItem]

    var id: String { tag }
}

struct Comment: Decodable, Identifiable {
    let id: Int64
    let parentId: Int64?
    let author: Author
    let body: String
    let createdAt: Date?
    let likeCount: Int64?
}
