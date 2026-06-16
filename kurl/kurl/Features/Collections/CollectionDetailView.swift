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
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    /// 내 컬렉션일 때만 수정·삭제·끊기 — 남의 공개 컬렉션은 보기만.
    private var isOwner: Bool {
        detail?.curatorUsername != nil && detail?.curatorUsername == AuthStore.shared.me?.username
    }

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
        .toolbar {
            if isOwner, let detail {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEdit = true
                        } label: {
                            Label("수정", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("컬렉션 삭제", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.brand)
                    .accessibilityLabel(Text("컬렉션 관리"))
                    // detail 변화에 메뉴가 최신 값을 쓰도록 id 고정.
                    .id(detail.id)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let detail {
                EditCollectionSheet(
                    id: detail.id, initialTitle: detail.title, initialBlurb: detail.blurb,
                    initialVisibility: detail.visibility
                ) { Task { await load() } }
            }
        }
        .alert("이 컬렉션을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) { Task { await deleteCollection() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("담긴 연결도 함께 사라져요. 연결된 글·노트 자체는 지워지지 않아요.")
        }
        .task { await load() }
    }

    private func disconnect(_ item: ConnectionItem) async {
        do {
            try await CollectionsAPI.disconnect(collectionId: collectionId, connectionId: item.id)
            await load()
        } catch {
            ToastCenter.shared.show(String(localized: "연결을 끊지 못했습니다"))
        }
    }

    private func deleteCollection() async {
        do {
            try await CollectionsAPI.delete(id: collectionId)
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "컬렉션을 삭제하지 못했습니다"))
        }
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
                    .typeScale(.lede)
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
        .contentShape(Rectangle())
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    Task { await disconnect(item) }
                } label: {
                    Label("연결 끊기", systemImage: "link.badge.plus")
                }
            }
        }
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
