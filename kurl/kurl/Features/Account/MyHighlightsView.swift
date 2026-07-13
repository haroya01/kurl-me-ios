//
//  MyHighlightsView.swift
//  kurl
//

import SwiftUI

/// 내 하이라이트 — 내가 그은 구절을 **글별로 묶어** 본다. 같은 글의 구절은 한 묶음 아래 모이고,
/// 헤더(글 제목)나 구절 행을 탭하면 원문으로. 검색으로 구절·글 제목을 좁힌다.
/// 서재의 다른 면(북마크·좋아요·구독)과 같은 글 행 문법.
struct MyHighlightsView: View {
    @State private var items: [MyHighlightView] = []
    @State private var connectTarget: MyHighlightView?
    @State private var pendingDelete: MyHighlightView?
    @State private var showDeleteConfirm = false
    @State private var loading = true
    @State private var failed = false
    @State private var query = ""

    /// 같은 글의 구절을 한 묶음으로 — 첫 등장 순서(최근순)를 보존한다.
    private struct PostGroup: Identifiable {
        let key: String
        let title: String
        let username: String
        let slug: String
        let items: [MyHighlightView]
        var id: String { key }
    }

    private var visibleGroups: [PostGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty ? items : items.filter {
            $0.quote.lowercased().contains(q) || $0.postTitle.lowercased().contains(q)
        }
        var order: [String] = []
        var map: [String: [MyHighlightView]] = [:]
        for it in filtered {
            let key = "\(it.postUsername)/\(it.postSlug)"
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(it)
        }
        return order.compactMap { key in
            guard let arr = map[key], let first = arr.first else { return nil }
            return PostGroup(
                key: key, title: first.postTitle, username: first.postUsername,
                slug: first.postSlug, items: arr)
        }
    }

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed {
                // 실패는 빈 200 과 구분 — 서재 형제 화면들의 실패 상태와 같은 문법.
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("다시 시도") { Task { loading = true; await load() } }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("하이라이트한 구절이 없습니다", systemImage: "highlighter")
                } description: {
                    Text("글을 읽다 마음에 닿는 문장을 길게 눌러 하이라이트해 보세요.")
                } actions: {
                    Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            } else if visibleGroups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                        section(group)
                            .modifier(QuietAppear(index: min(index, 8)))
                        if index < visibleGroups.count - 1 { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("내 하이라이트")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query, placement: .navigationBarDrawer(displayMode: .always),
            prompt: "구절·글 검색")
        .sheet(item: $connectTarget) { h in
            ConnectSheet(
                targetKind: "하이라이트", targetTitle: h.quote,
                blockType: .highlight, refId: h.id)
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("이 하이라이트를 삭제할까요?", isPresented: $showDeleteConfirm, presenting: pendingDelete) { item in
            Button("삭제", role: .destructive) { delete(item) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("메모나 답글이 딸려 있으면 함께 사라져요. 되돌릴 수 없어요.")
        }
    }

    /// 실패를 빈 배열로 삼키지 않는다 — 이미 목록이 있으면 유지하고, 빈 화면일 때만 실패 상태로.
    private func load() async {
        failed = false
        do {
            items = try await HighlightsAPI.mine()
            loading = false
        } catch {
            loading = false
            if items.isEmpty { failed = true }
        }
    }

    // MARK: 글 묶음

    private func section(_ group: PostGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 글 헤더 — 같은 글의 구절들이 이 아래 모인다. 탭 = 원문.
            // 클로저형 링크 — 계정 스택 혼용 함정 회피(값 기반은 이 깊이서 항해 안 함).
            NavigationLink {
                RouteView(route: .post(username: group.username, slug: group.slug))
                    .environment(\.tabBarVisibility, nil)
            } label: {
                HStack(spacing: 6) {
                    Text(group.title)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("·").foregroundStyle(Palette.faint)
                    Text(group.username)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(group.items.count)")
                        .foregroundStyle(Palette.faint)
                }
                .typeScale(.meta)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                quoteRow(item)
                if idx < group.items.count - 1 {
                    Hairline().padding(.leading, 8)
                }
            }
        }
    }

    private func quoteRow(_ item: MyHighlightView) -> some View {
        // 클로저형 링크 — 계정 스택 혼용 함정 회피(값 기반은 이 깊이서 항해 안 함).
        NavigationLink {
            RouteView(route: .post(username: item.postUsername, slug: item.postSlug))
                .environment(\.tabBarVisibility, nil)
        } label: {
            // 그은 구절 — 본문에서 칠한 그린 워시를 그대로.
            Text(item.quote)
                .typeScale(.body)
                .foregroundStyle(Palette.body)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Palette.highlightWash,
                    in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .contextMenu {
            Button { connectTarget = item } label: {
                Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
            }
            Button(role: .destructive) {
                pendingDelete = item
                showDeleteConfirm = true
            } label: {
                Label("하이라이트 삭제", systemImage: "trash")
            }
        }
    }

    /// 그은 구절 삭제 — 낙관적으로 목록에서 즉시 빼고, 실패하면 자리째 되돌리고 토스트로 알린다.
    private func delete(_ item: MyHighlightView) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let snapshot = items
        withAnimation(.snappy(duration: 0.25)) {
            items.remove(at: idx)
        }
        Task {
            do {
                try await HighlightsAPI.delete(id: item.id)
            } catch {
                withAnimation(.snappy(duration: 0.25)) { items = snapshot }
                ToastCenter.shared.show(String(localized: "하이라이트를 삭제하지 못했습니다"))
            }
        }
    }
}
