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
                if detail.kind == .path {
                    // PATH = reading path. 리스트가 아니라 순번으로 잇는 가이드 워크(문장→왜→문장).
                    pathWalk(detail)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(detail.connections.enumerated()), id: \.element.id) {
                            index, item in
                            connectionCell(item)
                                .modifier(QuietAppear(index: index))
                            if index < detail.connections.count - 1 {
                                Hairline().padding(.leading, 14)
                            }
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
            .typeScale(.meta)
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
                        .typeScale(.body)
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

    // MARK: 길(PATH) — 순번으로 잇는 가이드 워크. 큐레이터의 "왜"가 문장과 문장을 잇는 흐름.

    private func pathWalk(_ detail: CollectionDetail) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(detail.connections.enumerated()), id: \.element.id) { index, item in
                pathStepCell(index: index, total: detail.connections.count, item: item)
                    .modifier(QuietAppear(index: index))
            }
        }
        .padding(.top, 4)
    }

    private func pathStepCell(index: Int, total: Int, item: ConnectionItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // 순번 노드 + 다음 문장으로 잇는 세로 선 — "걷는다"는 신호.
            VStack(spacing: 0) {
                Text("\(index + 1)")
                    .font(.system(size: 12 * metaUnit, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Palette.accent.opacity(0.12)))
                if index < total - 1 {
                    Rectangle()
                        .fill(Palette.hairlineStrong)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let why = item.why {
                    // 큐레이터가 앞 문장에서 잇는 말 = 흐름의 목소리.
                    Text(why)
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BlockPreview(block: item.block)
            }
            .padding(.bottom, index < total - 1 ? 24 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    Task { await disconnect(item) }
                } label: {
                    Label("이 문장 빼기", systemImage: "minus.circle")
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
