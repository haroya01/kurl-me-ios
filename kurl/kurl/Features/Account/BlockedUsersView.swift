//
//  BlockedUsersView.swift
//  kurl
//

import SwiftUI

/// 차단한 사용자 관리 — 차단 해제(App Store 1.2 UGC 요건의 관리 면). BlockStore 가 단일 진실원이라
/// 해제하면 목록에서 즉시 빠지고, 그 작가의 콘텐츠도 다시 보인다.
struct BlockedUsersView: View {
    @State private var loading = true
    /// 로드 실패 — 빈 목록과 구분해야 '차단자 없음'으로 위장하지 않는다(해제하러 온 사용자의 막다른 길 방지).
    @State private var failed = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            Color.clear.frame(height: 8)
            if loading && BlockStore.shared.blocked.isEmpty {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed && BlockStore.shared.blocked.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "불러오지 못했습니다"), systemImage: "wifi.exclamationmark")
                } description: {
                    Text("연결을 확인하고 다시 시도해 주세요.")
                } actions: {
                    Button(String(localized: "다시 시도")) { Task { await load() } }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            } else if BlockStore.shared.blocked.isEmpty {
                ContentUnavailableView {
                    Label("차단한 사용자가 없어요", systemImage: "hand.raised")
                } description: {
                    Text("작가 페이지의 ⋯ 메뉴에서 차단할 수 있어요.")
                }
                .padding(.top, 60)
            } else {
                let items = BlockStore.shared.blocked
                LazyVStack(spacing: 0) {
                    ForEach(items) { u in
                        row(u)
                        if u.id != items.last?.id { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("차단한 사용자")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        failed = false
        // 이미 받아둔 목록이 있으면 실패해도 stale 목록을 유지한다 — failed 는 목록이 빌 때만 화면에 뜬다.
        let ok = await BlockStore.shared.reload()
        failed = !ok
        loading = false
    }

    private func row(_ u: InteractionsAPI.BlockedUser) -> some View {
        HStack(spacing: 12) {
            avatar(u.avatarUrl)
            Text(u.username)
                .typeScale(.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            Button("차단 해제") {
                Task {
                    do {
                        try await BlockStore.shared.unblock(id: u.id, username: u.username)
                        ToastCenter.shared.show(String(localized: "차단을 해제했어요"))
                    } catch {
                        ToastCenter.shared.show(String(localized: "해제하지 못했어요"))
                    }
                }
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.link)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func avatar(_ url: String?) -> some View {
        if let url, let parsed = URL(string: url) {
            RemoteImage(url: parsed) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    Circle().fill(Palette.hairline)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Circle().fill(Palette.hairline).frame(width: 36, height: 36)
        }
    }
}
