//
//  MyReadingHistoryView.swift
//  kurl
//

import SwiftUI

/// 읽기 기록 — 내가 읽은 글을 최신순으로. 행 탭 = 그 글로, 행 끝 × = 한 건 잊기, 상단 = 전체 지우기.
/// 사적 기록이라 본인만 본다(서재의 다른 면과 같은 글 행 문법, 무한 스크롤).
struct MyReadingHistoryView: View {
    @State private var items: [ReadingHistoryEntry] = []
    @State private var page = 0
    @State private var hasNext = false
    @State private var loading = false
    @State private var loadingMore = false
    @State private var loadedOnce = false
    @State private var failed = false
    @State private var confirmClear = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading && items.isEmpty {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed && items.isEmpty {
                // 빈 200 과 구분되는 네트워크 오류 — 사적 기록이라 "없어요"로 위장하면 삭제로 오해한다.
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("다시 시도") { Task { await reload() } }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            } else if loadedOnce && items.isEmpty {
                ContentUnavailableView {
                    Label("아직 읽기 기록이 없어요", systemImage: "clock")
                } description: {
                    Text("글을 읽으면 여기에 기록돼요. 기록은 나만 봅니다.")
                } actions: {
                    Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 56)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item)
                            .modifier(QuietAppear(index: index))
                            .task {
                                if index == items.count - 1 { await loadMore() }
                            }
                        if index < items.count - 1 { Hairline() }
                    }
                    if loadingMore {
                        KurlLoadingMark()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
            }
        }
        .navigationTitle("읽기 기록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("지우기") { confirmClear = true }
                        .tint(.brand)
                }
            }
        }
        // 알럿(중앙 모달) — confirmationDialog 은 regular width·세로 모두 부리 팝오버로 새어 나갔다.
        .alert("전체 기록을 지울까요?", isPresented: $confirmClear) {
            Button("기록 지우기", role: .destructive) { clearAll() }
            Button("취소", role: .cancel) {}
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func row(_ item: ReadingHistoryEntry) -> some View {
        HStack(spacing: 11) {
            // 아바타 → 작가 프로필(글이 아니라 사람). 제목·핸들 탭은 글로.
            // 클로저형 링크 — 계정 스택 혼용 함정 회피(값 기반은 이 깊이서 항해 안 함).
            NavigationLink {
                RouteView(route: .author(username: item.username))
                    .environment(\.tabBarVisibility, nil)
            } label: {
                AvatarView(author: item.asAuthor, size: 40)
            }
            .buttonStyle(.plain)
            NavigationLink {
                RouteView(route: .post(username: item.username, slug: item.slug))
                    .environment(\.tabBarVisibility, nil)
            } label: {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .typeScale(.titleSmall)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("@\(item.username)")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())

            Button {
                forget(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .expandTapTarget(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기록에서 지우기")
        }
        .padding(.vertical, 10)
    }

    private func reload() async {
        loading = true
        loadingMore = false
        failed = false
        do {
            let res = try await ReadingHistoryAPI.list(page: 0)
            page = 0
            items = res.items
            hasNext = res.hasNext
        } catch {
            // 실패는 빈 결과가 아니다 — 떠 있던 목록·페이지 상태는 보존하고, 처음부터 실패면 재시도 상태.
            if items.isEmpty { failed = true }
        }
        loading = false
        loadedOnce = true
    }

    private func loadMore() async {
        guard hasNext, !loading, !loadingMore else { return }
        loadingMore = true
        if let res = try? await ReadingHistoryAPI.list(page: page + 1) {
            items += res.items
            page = res.page
            hasNext = res.hasNext
        }
        // 실패하면 hasNext 는 그대로 둬서 마지막 행이 다시 보일 때 재시도된다.
        loadingMore = false
    }

    /// 낙관적 — 즉시 빼되 실패하면 스냅샷으로 되돌린다(사적 기록이라 조용히 사라지면 오해한다).
    private func forget(_ item: ReadingHistoryEntry) {
        let snapshot = items
        items.removeAll { $0.postId == item.postId }
        Task {
            do {
                try await ReadingHistoryAPI.forget(postId: item.postId)
            } catch {
                items = snapshot
                ToastCenter.shared.show(String(localized: "기록을 지우지 못했습니다"))
            }
        }
    }

    /// 전체 삭제도 같은 규칙 — 페이지 상태까지 함께 스냅샷.
    private func clearAll() {
        let snapshot = items
        let hadNext = hasNext
        let prevPage = page
        items = []
        hasNext = false
        Task {
            do {
                try await ReadingHistoryAPI.clear()
            } catch {
                items = snapshot
                hasNext = hadNext
                page = prevPage
                ToastCenter.shared.show(String(localized: "기록을 지우지 못했습니다"))
            }
        }
    }
}
