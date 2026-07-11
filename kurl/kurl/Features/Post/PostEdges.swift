//
//  PostEdges.swift
//  kurl
//
//  글 = 엣지가 보이는 노드(§0). 다 읽은 뒤 본문 끝에서, 이 글이 놓인 길 · 이어진 것 · 이은 사람으로
//  엣지를 따라 나간다 — 시간순 "다음 글"이 아니라 사람이 손으로 엮은 연결로. 막다른 길을 지운다.
//  전부 공개 read(미로그인도 본다)라 게이트 없이 뜬다. 엣지가 하나도 없으면 통째로 그려지지 않고,
//  태그 기반 추천(작가 카드·이 작가의 다른 글)이 아래에 폴백으로 남는다.
//
//  §1: 여긴 종이 세계(콘텐츠)라 유리 없이 slate + hairline + 그린 한 가닥. 그린은 비텍스트
//  마커(길 글리프)에만(§10.3 accent 600) — 카피는 조용한 슬레이트로. 노드-엣지 그림은 그리지 않는다.
//

import SwiftUI

/// 본문 끝의 엣지 섹션 — 컬렉션 소속·이어진 블록·이은 큐레이터. 세 갈래 중 실린 것만 그린다.
struct PostEdges: View {
    let postId: Int64
    /// 이 글 작가 — "이 글을 엮은 사람"(취향 겹치는 큐레이터)을 그의 kindred 로 잇는다.
    let authorUsername: String

    @State private var collections: [CollectionSummary] = []
    @State private var related: [RelatedBlock] = []
    @State private var kindred: [KindredCurator] = []
    @State private var loaded = false

    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 11

    private var hasEdges: Bool {
        !collections.isEmpty || !related.isEmpty || !kindred.isEmpty
    }

    var body: some View {
        // 항상 존재하는 0높이 앵커에 로드를 건다 — 빈 뷰가 LazyVStack 안에서 .task 를 안 태우는
        // 함정을 피한다(엣지 없을 땐 아래 콘텐츠가 통째로 비지만 로드는 이 앵커가 보장한다).
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 1)
                .task(id: postId) { await load() }

            if hasEdges {
                VStack(alignment: .leading, spacing: 0) {
                    Hairline().padding(.bottom, 20)

                    if !collections.isEmpty { pathsSection }
                    if !related.isEmpty { relatedSection }
                    if !kindred.isEmpty { kindredSection }
                }
                .padding(.vertical, 6)
                .transition(.opacity)
            }
        }
    }

    // MARK: 이 글이 놓인 길 — 담긴 공개 컬렉션(소속 한 올과 같은 그린 글리프 문법)

    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailHeading("이 글이 놓인 길")
            ForEach(collections) { collection in
                NavigationLink(value: Route.collection(id: collection.id)) {
                    pathChip(collection)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 길/컬렉션 한 줄(리치) — 그린 ↳ 글리프(§10.3 비텍스트=accent) + 제목, 그 아래 조용한 메타 한 줄.
    /// 메타 = "@큐레이터 · N번째 / 전체 M"(#607 curatorUsername·position·total). 순서 맥락 없으면 담긴 수로
    /// 폴백. 아바타·그림 없이 종이 위 슬레이트 텍스트(§1·§10) — 초록은 오직 글리프 한 실.
    private func pathChip(_ collection: CollectionSummary) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: collection.kind == .path ? "arrow.turn.down.right" : "square.grid.2x2")
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                pathMeta(collection)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.faint)
                .padding(.top, 3)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 길 메타 한 줄 — 큐레이터와 순서를 한 번역 문자열로(로케일이 조사·어순 소유). position/total 이 오면
    /// "@큐레이터 · N번째 / 전체 M", 큐레이터만 있으면 "@큐레이터 · M편", 둘 다 없으면 "M편"으로 폴백.
    private func pathMeta(_ c: CollectionSummary) -> Text {
        // 전체 편 수 — total 은 글 단위 소속 응답에만 오고(#607), 목록 응답엔 count 만 온다.
        // total 을 분모로 못 박으면 순서 맥락이 프로덕션에서 통째로 빠지므로 count 로 폴백한다.
        let m = c.total ?? c.count
        if let curator = c.curatorUsername, let pos = c.position {
            return Text("@\(curator) · \(pos)번째 / 전체 \(m)")
        }
        if let curator = c.curatorUsername {
            return Text("@\(curator) · \(m)편")
        }
        return Text("\(m)편")
    }

    // MARK: 이어진 것 — 같은 공개 컬렉션에 나란히 엮인 다른 블록(공동 등장)

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            RailHeading("이어진 것")
            ForEach(related) { item in
                // 발견 흐름·컬렉션 상세와 같은 블록 실루엣을 재사용 — 글=카드, 하이라이트=그린 룰,
                // 노트=종이 위 그대로. 인게이지 표식은 끈다(본문 끝은 조용히).
                BlockPreview(block: item.block)
            }
        }
        .padding(.top, collections.isEmpty ? 0 : 26)
    }

    // MARK: 이 글을 엮은 사람 — 같은 것을 자기 컬렉션에도 엮은 취향 겹치는 큐레이터

    private var kindredSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("이 글을 엮은 사람")
                .padding(.bottom, 6)
            ForEach(Array(kindred.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: Route.author(username: item.curator.username)) {
                    kindredRow(item)
                }
                .buttonStyle(.plain)
                if index < kindred.count - 1 {
                    Hairline().padding(.leading, 55)
                }
            }
        }
        .padding(.top, (collections.isEmpty && related.isEmpty) ? 0 : 26)
    }

    /// 큐레이터 한 줄 — 컬렉션 상세의 kindred 행과 같은 문법(아바타 + 이름·소개 + 겹친 수).
    private func kindredRow(_ item: KindredCurator) -> some View {
        HStack(spacing: 11) {
            AvatarView(author: item.curator, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(item.curator.username)")
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let bio = item.curator.bio, !bio.isEmpty {
                    Text(bio)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(item.sharedItems)개 함께 엮음")
                .typeScale(.meta)
                .foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: 로드 — 세 공개 엔드포인트를 나란히. 하나가 비어도 나머지는 그린다.

    private func load() async {
        guard !loaded else { return }
        loaded = true
        // 세 요청을 병렬로 — 서로를 기다리지 않게. 실패는 조용히 흡수(엣지는 부가 표면, 읽기를 막지 않는다).
        async let collectionsTask = try? CollectionsAPI.publicPostCollectionsBatch(ids: [postId])
        async let relatedTask = try? CollectionsAPI.relatedBlocks(blockType: "POST", refId: postId)
        async let kindredTask = try? CollectionsAPI.kindredCurators(username: authorUsername)

        let fetchedCollections = (await collectionsTask)?.first?.collections ?? []
        let fetchedRelated = (await relatedTask) ?? []
        let fetchedKindred = (await kindredTask) ?? []

        collections = fetchedCollections
        related = fetchedRelated
        kindred = fetchedKindred
    }
}
