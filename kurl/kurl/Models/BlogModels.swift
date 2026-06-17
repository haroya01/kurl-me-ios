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

    private enum CodingKeys: String, CodingKey {
        case author, post, blocks, series
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decode(Author.self, forKey: .author)
        post = try container.decode(PostListItem.self, forKey: .post)
        series = try container.decodeIfPresent(PostSeriesNav.self, forKey: .series)
        // 디코드 순서를 안정 식별자로 못박는다 — blockOrder 가 nil 이어도 id 가 매 렌더 흔들리지 않게.
        let raw = try container.decode([PostBlock].self, forKey: .blocks)
        blocks = raw.enumerated().map { index, block in
            block.withDecodeIndex(index)
        }
    }
}

struct PostBlock: Decodable, Identifiable {
    let type: String
    let content: String?
    let blockOrder: Int?
    let cta: CtaInfo?
    /// 디코드 시점에 배열 인덱스로 박는 안정 식별자. blockOrder 가 nil 이어도 TOC 점프·딥링크가 안 깨진다.
    private(set) var decodeIndex: Int = 0

    private enum CodingKeys: String, CodingKey {
        case type, content, blockOrder, cta
    }

    var id: Int { blockOrder ?? decodeIndex }
    var kind: BlockKind { BlockKind(rawValue: type) ?? .unknown }

    func withDecodeIndex(_ index: Int) -> PostBlock {
        var copy = self
        copy.decodeIndex = index
        return copy
    }
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

struct Comment: Decodable, Identifiable, Equatable {
    let id: Int64
    let parentId: Int64?
    let author: Author
    let body: String
    let createdAt: Date?
    let likeCount: Int64?
}
