//
//  FeedRow.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct RowLayout<Top: View, Byline: View>: View {
    var title: String?
    var excerpt: Text?
    var excerptIsBody = false
    var cover: URL?
    var read = false
    @ViewBuilder var top: Top
    @ViewBuilder var byline: Byline

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var thumbSize: CGFloat = 72

    private var thumbnail: URL? {
        typeSize.isAccessibilitySize ? nil : cover
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    top
                    if let title {
                        Text(title)
                            .typeScale(.title)
                            .foregroundStyle(read ? Palette.secondary : Palette.ink)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(read ? Text("\(title), 읽음") : Text(title))
                    }
                    if let excerpt {
                        excerpt
                            .typeScale(.lede)
                            .foregroundStyle(excerptIsBody && !read ? Palette.ink : Palette.secondary)
                            .lineLimit(excerptIsBody ? 3 : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                byline
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let thumbnail {
                RowThumbnail(url: thumbnail, size: thumbSize)
            }
        }
        // 행 높이 = max(글 열, 썸네일). 그 높이로 글 열을 다시 채워 작가 줄이 썸네일 아래 끝선까지 내려앉는다.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct RowThumbnail: View {
    let url: URL
    let size: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.radiusInner, style: .continuous)
    }

    var body: some View {
        // 가로 커버를 정사각으로 채우므로 짧은 변 기준 해상도가 필요하다 — 긴 변 상한을 두 배로 받는다.
        RemoteImage(url: url, maxPixel: size * 2) { phase in
            if case .success(let image) = phase {
                // 채움 이미지는 프레임 밖으로 넘친다 — 클립은 그림만 자르고 히트는 못 잘라, 이웃 행 탭을 먹는다.
                image.resizable().scaledToFill().allowsHitTesting(false)
            } else {
                Palette.hairline
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.hairlineStrong.opacity(0.5), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

struct FeedRow: View {
    let item: FeedItem
    var omittingTag: String?
    var belonging: [CollectionSummary] = []
    var linked = false

    private var tag: String? {
        item.renderableTags.first { $0.caseInsensitiveCompare(omittingTag ?? "") != .orderedSame }
    }

    var body: some View {
        RowLayout(
            title: item.title.cleanedPreview,
            excerpt: item.excerpt.flatMap { $0.isEmpty ? nil : Text($0.cleanedPreview) },
            cover: item.ogImageUrl.flatMap { URL(string: $0) },
            read: PostReadStore.shared.isRead(item.id)
        ) {
            if let tag {
                tagLine(tag)
            }
        } byline: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AuthorByline(author: item.author, date: item.publishedAt, linked: linked)
                    Spacer(minLength: 0)
                    if BookmarkStore.shared.contains(item.id) {
                        bookmarkMark
                    }
                }
                if !belonging.isEmpty {
                    BelongingLine(collections: belonging)
                }
            }
        }
        .onAppear {
            Task { await BookmarkStore.shared.hydrateIfNeeded() }
            Task { await BlockStore.shared.hydrateIfNeeded() }
        }
    }

    @ViewBuilder
    private func tagLine(_ tag: String) -> some View {
        let label = Text("#\(tag)")
            .typeScale(.meta)
            .foregroundStyle(Palette.secondary)
        if linked {
            NavigationLink(value: Route.tag(tag)) {
                label.expandTapTarget(8)
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var bookmarkMark: some View {
        Button {
            CardQuickActions.bookmark(item)
        } label: {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accentMarker)
                .expandTapTarget(14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("북마크 해제")
    }
}

struct PostRow: View {
    let item: PostListItem

    private var tag: String? { ContentValidity.renderableTags(item.tags).first }

    var body: some View {
        RowLayout(
            title: item.title.cleanedPreview,
            excerpt: item.excerpt.flatMap { $0.isEmpty ? nil : Text($0.cleanedPreview) },
            cover: item.ogImageUrl.flatMap { URL(string: $0) },
            read: PostReadStore.shared.isRead(item.id)
        ) {
            if item.pinned || tag != nil {
                HStack(spacing: 6) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accent)
                    }
                    if let tag {
                        Text("#\(tag)")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        } byline: {
            if let date = item.publishedAt {
                Text(date.relativeShort)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct AuthorByline: View {
    let author: Author
    var date: Date?
    var linked = false

    var body: some View {
        HStack(spacing: 6) {
            if linked {
                // 행 링크 안의 링크 — buttonStyle 이 있어야 바깥 행 링크가 이 탭을 삼키지 않는다.
                NavigationLink(value: Route.author(username: author.username)) {
                    name
                }
                .buttonStyle(.plain)
            } else {
                name
            }
            if let date {
                Text(verbatim: "·").foregroundStyle(Palette.faint)
                Text(date.relativeShort)
            }
        }
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
        .lineLimit(1)
    }

    private var name: some View {
        HStack(spacing: 6) {
            AvatarView(author: author, size: 16)
            Text(author.username)
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .padding(.horizontal, -10)
    }
}

private struct BelongingLine: View {
    let collections: [CollectionSummary]

    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 10

    var body: some View {
        if let lead = collections.first {
            NavigationLink(value: CollectionRef(id: lead.id)) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: glyph, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    caption(title: lead.title)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .typeScale(.meta)
                .expandTapTarget(4)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isLink)
        }
    }

    private func caption(title: String) -> Text {
        let others = collections.count - 1
        if others == 0 {
            return Text("‘\(title)’에 담김")
        }
        return Text("‘\(title)’ 외 \(others)개 컬렉션에 담김")
    }
}

extension View {
    func rowDivider(_ visible: Bool) -> some View {
        overlay(alignment: .top) {
            if visible { Hairline() }
        }
    }
}

/// 읽은(연 적 있는) 글의 기기 로컬 기억 — 시리즈 진행이 읽는다.
/// 서버에 읽음 모델이 없어 기기에만, 최근 600개. `@Observable` 이라 글을 읽고 돌아오면
/// 시리즈 회차 체크·진행 막대가 곧바로 갱신된다(푸시된 채로 바뀌어도 pop 시 최신 반영).
@MainActor
@Observable
final class PostReadStore {
    static let shared = PostReadStore(key: "postReadIds", seedFlag: "--seed-read")
    /// 시리즈에 든 노트 — 글과 id 공간이 달라 따로 기억한다(같은 숫자 id 가 겹치지 않게).
    static let notes = PostReadStore(key: "noteReadIds", seedFlag: "--seed-read-notes")

    private let key: String
    private static let cap = 600
    // 단일 진실원 = 메모리. order 가 최근순(오래된 것 앞) 링버퍼이고, lookup 은 set 으로 O(1).
    // 둘은 항상 같이 갱신 — 쓸 때 UserDefaults 를 되읽지 않는다(과거 분기 원인).
    private var order: [Int64]
    private var lookup: Set<Int64>

    private init(key: String, seedFlag: String) {
        self.key = key
        let stored = ((UserDefaults.standard.array(forKey: key) as? [NSNumber]) ?? [])
            .map(\.int64Value)
        order = stored
        lookup = Set(stored)
        // 검증용 시드 — 목 모드에서 시리즈 진행/체크 상태를 그려보기 위함(`--seed-read 8001,8002`).
        if Config.useMocks, let seed = Config.launchValue(after: seedFlag) {
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
        UserDefaults.standard.set(order.map(NSNumber.init(value:)), forKey: key)
    }

    /// 로그아웃 시 — 읽음 기록은 기기 로컬이라 계정 전환 시 비워야 다음 사용자가 이전
    /// 사용자의 읽음·시리즈 진행 상태를 물려받지 않는다.
    func reset() {
        order = []
        lookup = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension String {
    /// 카드 미리보기(제목·요약)용 마크다운 정리 — 웹 cleanPreview 와 같은 규칙. 저장된 excerpt 에
    /// WYSIWYG 가 남긴 raw md 가 안 새게: 이스케이프(\[ \] \* …) 해제 · 선두 heading(#) 제거 ·
    /// 링크는 라벨만 · 강조 기호 제거. '#'은 단어 시작에서만 떼서 "C#"·"a#b"는 보존.
    var cleanedPreview: String {
        var s = self
        let steps: [(String, String)] = [
            (#"\\([^\sA-Za-z0-9])"#, "$1"),
            (#"(^|\s)#{1,6}(?=\S)"#, "$1"),
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),
            (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"[*_`~]+"#, ""),
            (#"\s+"#, " "),
        ]
        for (pattern, template) in steps {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
