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
                    .typeScale(featured ? .featured : .title)
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
                        .font(.system(size: 12, weight: .medium))
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

/// 구독함 행 — 카드가 아니라 "도착한 글". 미읽음은 그린 점, 읽음 기억은 기기 로컬.
struct InboxRow: View {
    let item: FeedItem

    private var read: Bool { PostReadStore.shared.isRead(item.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(author: item.author, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !read {
                        Circle().fill(Palette.accent).frame(width: 7, height: 7)
                    }
                    Text(item.author.username)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    if let date = item.publishedAt {
                        Text("·").foregroundStyle(Palette.faint)
                        Text(date.relativeShort)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                Text(item.title)
                    .font(.system(size: 16, weight: read ? .regular : .semibold))
                    .foregroundStyle(read ? Palette.body : Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let urlString = item.ogImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Palette.hairline)
                }
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// 읽은(연 적 있는) 글의 기기 로컬 기억 — 구독함 미읽음 점과 시리즈 진행이 함께 읽는다.
/// 서버에 읽음 모델이 없어 기기에만, 최근 600개. `@Observable` 이라 글을 읽고 돌아오면
/// 시리즈 회차 체크·진행 막대가 곧바로 갱신된다(푸시된 채로 바뀌어도 pop 시 최신 반영).
@MainActor
@Observable
final class PostReadStore {
    static let shared = PostReadStore()

    private static let key = "postReadIds"
    private var ids: Set<Int64>

    private init() {
        let stored = (UserDefaults.standard.array(forKey: Self.key) as? [NSNumber]) ?? []
        ids = Set(stored.map(\.int64Value))
        // 검증용 시드 — 목 모드에서 시리즈 진행/체크 상태를 그려보기 위함(`--seed-read 8001,8002`).
        if Config.useMocks, let seed = Config.launchValue(after: "--seed-read") {
            ids.formUnion(seed.split(separator: ",").compactMap { Int64($0) })
        }
    }

    func isRead(_ id: Int64) -> Bool { ids.contains(id) }

    func markRead(_ id: Int64) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        var stored = ((UserDefaults.standard.array(forKey: Self.key) as? [NSNumber]) ?? [])
            .map(\.int64Value)
        stored.append(id)
        if stored.count > 600 { stored.removeFirst(stored.count - 600) }
        UserDefaults.standard.set(stored.map(NSNumber.init(value:)), forKey: Self.key)
    }
}

/// 조건 분기에서 서로 다른 ButtonStyle 을 한 자리에 — 타입 소거.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
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
