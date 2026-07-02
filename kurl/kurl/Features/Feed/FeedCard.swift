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
                        .typeScale(.eyebrow)
                        .foregroundStyle(Palette.secondary)
                }
                if let tag = item.tags.first {
                    Text("#\(tag)")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
                Text(item.title)
                    .typeScale(featured ? .featured : .title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(featured ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let excerpt = item.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                MetaRow(author: item.author.username, date: item.publishedAt, likes: item.likeCount)
                    .padding(.top, 2)
            }

            if let urlString = item.ogImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        // 로딩·실패 공통 — 맨 회색 면 대신 옅은 kurl 마크 워터마크(otherPostCover 와 같은 언어).
                        ZStack {
                            Palette.hairline
                            KurlMark(drawn: [true, true, true], tint: Palette.hairlineStrong)
                                .frame(width: 30, height: 18)
                        }
                    }
                }
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
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
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Text(item.title)
                .typeScale(.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MetaRow(author: nil, date: item.publishedAt, likes: item.likeCount)
                .padding(.top, 2)
        }
        .padding(.vertical, 16)
        // 행은 컬럼 전폭으로 좌측 정렬 — 안 그러면 내용 폭으로 줄어 부모(center)에서 가운데로 떠
        // "기사 목록이 가운데 정렬"되어 보인다(작가 페이지 버그).
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 읽은(연 적 있는) 글의 기기 로컬 기억 — 시리즈 진행이 읽는다.
/// 서버에 읽음 모델이 없어 기기에만, 최근 600개. `@Observable` 이라 글을 읽고 돌아오면
/// 시리즈 회차 체크·진행 막대가 곧바로 갱신된다(푸시된 채로 바뀌어도 pop 시 최신 반영).
@MainActor
@Observable
final class PostReadStore {
    static let shared = PostReadStore()

    private static let key = "postReadIds"
    private static let cap = 600
    // 단일 진실원 = 메모리. order 가 최근순(오래된 것 앞) 링버퍼이고, lookup 은 set 으로 O(1).
    // 둘은 항상 같이 갱신 — 쓸 때 UserDefaults 를 되읽지 않는다(과거 분기 원인).
    private var order: [Int64]
    private var lookup: Set<Int64>

    private init() {
        let stored = ((UserDefaults.standard.array(forKey: Self.key) as? [NSNumber]) ?? [])
            .map(\.int64Value)
        order = stored
        lookup = Set(stored)
        // 검증용 시드 — 목 모드에서 시리즈 진행/체크 상태를 그려보기 위함(`--seed-read 8001,8002`).
        if Config.useMocks, let seed = Config.launchValue(after: "--seed-read") {
            for id in seed.split(separator: ",").compactMap({ Int64($0) }) where lookup.insert(id).inserted {
                order.append(id)
            }
        }
    }

    func isRead(_ id: Int64) -> Bool { lookup.contains(id) }

    func markRead(_ id: Int64) {
        guard lookup.insert(id).inserted else { return }
        order.append(id)
        if order.count > Self.cap {
            let dropped = order.prefix(order.count - Self.cap)
            lookup.subtract(dropped)
            order.removeFirst(order.count - Self.cap)
        }
        UserDefaults.standard.set(order.map(NSNumber.init(value:)), forKey: Self.key)
    }

    /// 로그아웃 시 — 읽음 기록은 기기 로컬이라 계정 전환 시 비워야 다음 사용자가 이전
    /// 사용자의 읽음·시리즈 진행 상태를 물려받지 않는다.
    func reset() {
        order = []
        lookup = []
        UserDefaults.standard.removeObject(forKey: Self.key)
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
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
    }

    private var dot: some View {
        Text("·").foregroundStyle(Palette.faint)
    }
}
