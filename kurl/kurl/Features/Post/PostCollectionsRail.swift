//
//  PostCollectionsRail.swift
//  kurl
//
//  글 = 엣지가 보이는 노드(§0). 다 읽은 뒤 본문 끝에서, 이 글이 담긴 공개 컬렉션으로 나간다 — 시간순
//  "다음 글"이 아니라 사람이 손으로 엮은 연결로. 공개 read(미로그인도 본다)라 게이트 없이 뜬다.
//  담긴 공개 컬렉션이 없으면 그려지지 않는다.
//
//  §1: 여긴 종이 세계(콘텐츠)라 유리 없이 slate + hairline. 폴더 글리프·순번 배지도
//  보조색 — 카피도 조용한 슬레이트로. 노드-엣지 그림은 그리지 않는다.
//

import SwiftUI

struct PostCollectionsRail: View {
    let postId: Int64

    @State private var collections: [CollectionSummary] = []
    @State private var loaded = false

    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var lead: CGFloat = 20

    var body: some View {
        // 항상 존재하는 0높이 앵커에 로드를 건다 — 빈 뷰가 LazyVStack 안에서 .task 를 안 태우는
        // 함정을 피한다(엣지 없을 땐 아래 콘텐츠가 통째로 비지만 로드는 이 앵커가 보장한다).
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 1)
                .task(id: postId) { await load() }

            if !collections.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Hairline().padding(.bottom, 20)
                    pathsSection
                }
                .padding(.vertical, 6)
                .transition(.opacity)
            }
        }
    }

    // MARK: 이 글이 담긴 컬렉션 — 담긴 공개 컬렉션(소속 한 올과 같은 글리프 문법)

    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailHeading("이 글이 담긴 컬렉션")
            ForEach(collections) { collection in
                NavigationLink(value: Route.collection(id: collection.id)) {
                    pathChip(collection)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 순서 있는 컬렉션에서 이 글의 자리를 알 때만 순번 — 그 밖엔 담긴 수로 읽는다.
    private func step(_ c: CollectionSummary) -> Int? {
        c.isOrdered ? c.position : nil
    }

    private func pathChip(_ collection: CollectionSummary) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Group {
                if let step = step(collection) {
                    Text("\(step)")
                        .typeScale(.meta)
                        .fontWeight(.bold)
                        .foregroundStyle(Palette.secondary)
                        .frame(width: lead, height: lead)
                        .background(Circle().strokeBorder(Palette.secondary, lineWidth: 1))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: glyph, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(width: lead, alignment: .center)
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

    /// 메타 한 줄 — 로케일이 조사·어순을 갖도록 한 번역 문자열로. total 은 글 단위 소속 응답(#607)에만
    /// 오고 목록 응답엔 count 만 오므로 분모는 count 로 폴백한다.
    private func pathMeta(_ c: CollectionSummary) -> Text {
        let total = c.total ?? c.count
        if let pos = step(c) {
            if let curator = c.curatorUsername {
                return Text("@\(curator) · \(total)편 중 \(pos)번째")
            }
            return Text("\(total)편 중 \(pos)번째")
        }
        if let curator = c.curatorUsername {
            return Text("@\(curator) · \(c.count)개")
        }
        return Text("\(c.count)개")
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        // 실패는 조용히 흡수(엣지는 부가 표면, 읽기를 막지 않는다).
        let batch = try? await CollectionsAPI.publicPostCollectionsBatch(ids: [postId])
        collections = batch?.first?.collections ?? []
    }
}
