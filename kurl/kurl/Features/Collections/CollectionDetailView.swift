//
//  CollectionDetailView.swift
//  kurl
//
//  컬렉션 상세 = 연결된 블록(글·하이라이트·노트)이 섞여 흐르는 채널. 각 연결은 큐레이터의 한 줄
//  이유를 단다 — 단순 북마크와 컬렉션을 가르는 영혼. 백엔드 `GET /collections/{id}`.
//

import SwiftUI

struct CollectionDetailView: View {
    let collectionId: Int64
    @State private var detail: CollectionDetail?
    @State private var loading = true
    @State private var failed = false
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if let detail {
                header(detail)
                Hairline().padding(.bottom, 4)
                LazyVStack(spacing: 0) {
                    ForEach(Array(detail.connections.enumerated()), id: \.element.id) { index, item in
                        connectionCell(item)
                            .modifier(QuietAppear(index: index))
                        if index < detail.connections.count - 1 {
                            Hairline().padding(.leading, 14)
                        }
                    }
                }
                if detail.connections.isEmpty {
                    emptyState
                }
            } else if failed {
                failedState
            }
        }
        .navigationTitle(detail?.title ?? "컬렉션")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Route.self) { RouteView(route: $0) }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            detail = try await CollectionsAPI.detail(id: collectionId)
            loading = false
        } catch {
            loading = false
            if detail == nil { failed = true }
        }
    }

    // MARK: 헤더

    private func header(_ detail: CollectionDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.title)
                .typeScale(.featured)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let blurb = detail.blurb {
                Text(blurb)
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if let curator = detail.curatorUsername {
                    AvatarView(
                        author: Author(id: 0, username: curator, bio: nil, avatarUrl: nil), size: 20)
                    Text(curator).foregroundStyle(Palette.ink)
                    Text("·").foregroundStyle(Palette.faint)
                }
                Image(systemName: detail.visibility.icon)
                    .font(.system(size: 11 * metaUnit, weight: .medium))
                Text(detail.visibility.label)
                Text("·").foregroundStyle(Palette.faint)
                Text("\(detail.connections.count)개")
            }
            .font(.system(size: 13 * metaUnit, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }

    // MARK: 연결 한 칸 — 왼쪽 실(연결 신호) + [이유 한 줄] + 블록

    private func connectionCell(_ item: ConnectionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.hairlineStrong)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 9) {
                if let why = item.why {
                    Text(why)
                        .font(.system(size: 15 * unit, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BlockPreview(block: item.block)
            }
        }
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("아직 연결된 글이 없어요", systemImage: "link")
        } description: {
            Text("글을 읽다 우하단 연결 버튼으로 이 컬렉션에 이어 보세요.")
        }
        .padding(.top, 40)
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } actions: {
            Button("다시 시도") { Task { loading = true; await load() } }
                .foregroundStyle(Palette.accent)
        }
        .padding(.top, 60)
    }
}
