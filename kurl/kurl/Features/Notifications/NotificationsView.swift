//
//  NotificationsView.swift
//  kurl
//

import SwiftUI

/// 알림 — 웹 벨과 같은 데이터. 행 탭 = 읽음 처리 + 대상(글/작가/시리즈)으로 이동,
/// 미읽음은 왼쪽 그린 점 하나로 조용히 표시한다.
struct NotificationsView: View {
    @State private var items: [AppNotification] = []
    @State private var nextCursor: Int64?
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingMore = false
    @State private var loadError: String?
    /// "모두 읽음" 성공 햅틱 트리거 — 글 완독 성공 햅틱과 같은 결의 확인음.
    @State private var markAllPulse = 0
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty, let loadError {
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                        .foregroundStyle(Palette.accent)
                }
                .padding(.top, 60)
            } else if items.isEmpty {
                ContentUnavailableView("알림이 없습니다", systemImage: "bell")
                    .padding(.top, 60)
            } else {
                list
            }
        }
        .navigationTitle("알림")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("모두 읽음") {
                    Task {
                        do {
                            try await NotificationsAPI.markAllRead()
                            withAnimation(.easeOut(duration: 0.25)) {
                                items = items.map(asRead)
                            }
                            markAllPulse += 1
                        } catch {
                            // 실패했는데 점만 사라지는 거짓 성공을 만들지 않는다.
                            ToastCenter.shared.show(String(localized: "읽음 처리하지 못했습니다"))
                        }
                    }
                }
                .font(.system(size: 13))
                .disabled(items.allSatisfy(\.read))
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sensoryFeedback(.success, trigger: markAllPulse)
    }

    @ViewBuilder
    private var list: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, notification in
            Group {
                if let route = route(for: notification) {
                    NavigationLink(value: route) {
                        row(notification)
                    }
                    .buttonStyle(RowButtonStyle())
                    .simultaneousGesture(TapGesture().onEnded {
                        markRead(notification)
                    })
                } else {
                    row(notification)
                        .onTapGesture { markRead(notification) }
                }
            }
            .task {
                if index >= items.count - 3 { await loadMore() }
            }
            if index < items.count - 1 { Hairline() }
        }
        if loadingMore {
            ProgressView().tint(Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }

    private func row(_ n: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(n.read ? Color.clear : Palette.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            AvatarView(
                author: Author(
                    id: 0, username: n.actorUsername ?? "?", bio: nil, avatarUrl: n.actorAvatarUrl),
                size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline(n))
                    .font(.system(size: 14 * unit, weight: n.read ? .regular : .medium))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = n.postTitle ?? n.seriesTitle {
                    Text(subtitle)
                        .font(.system(size: 13 * unit))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                if let date = n.createdAt {
                    Text(date.relativeShort)
                        .font(.system(size: 12 * unit))
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(n.read ? Text(verbatim: "") : Text("읽지 않음"))
    }

    private func headline(_ n: AppNotification) -> LocalizedStringKey {
        let actor = n.actorUsername ?? String(localized: "알 수 없는 사용자")
        switch n.type {
        case "LIKE": return "\(actor)님이 글을 좋아합니다"
        case "COMMENT": return "\(actor)님이 댓글을 남겼습니다"
        case "REPLY": return "\(actor)님이 답글을 남겼습니다"
        case "FOLLOW": return "\(actor)님이 팔로우하기 시작했습니다"
        case "SERIES_SUBSCRIBE": return "\(actor)님이 시리즈를 구독합니다"
        case "NEW_POST": return "\(actor)님이 새 글을 발행했습니다"
        case "MENTION": return "\(actor)님이 회원님을 언급했습니다"
        default: return "\(actor)"
        }
    }

    /// 알림 대상 라우팅 — 글이 있으면 글로, 팔로우는 작가로, 시리즈 구독은 내 시리즈로.
    /// 라우팅 재료가 비어 있으면 nil — 404 화면으로 푸시하지 않는다.
    private func route(for n: AppNotification) -> Route? {
        if let slug = n.postSlug, let author = n.postAuthorUsername, !author.isEmpty {
            return .post(username: author, slug: slug)
        }
        if let slug = n.seriesSlug, let mine = AuthStore.shared.me?.username, !mine.isEmpty {
            return .series(username: mine, slug: slug)
        }
        if let actor = n.actorUsername, !actor.isEmpty {
            return .author(username: actor)
        }
        return nil
    }

    private func markRead(_ n: AppNotification) {
        guard !n.read else { return }
        Task { try? await NotificationsAPI.markRead(id: n.id) }
        if let idx = items.firstIndex(where: { $0.id == n.id }) {
            items[idx] = asRead(items[idx])
        }
    }

    private func asRead(_ n: AppNotification) -> AppNotification {
        AppNotification(
            id: n.id, type: n.type, actorUsername: n.actorUsername,
            actorAvatarUrl: n.actorAvatarUrl, postId: n.postId, postSlug: n.postSlug,
            postTitle: n.postTitle, postAuthorUsername: n.postAuthorUsername,
            seriesId: n.seriesId, seriesSlug: n.seriesSlug, seriesTitle: n.seriesTitle,
            read: true, createdAt: n.createdAt)
    }

    private func load() async {
        do {
            let page = try await NotificationsAPI.list()
            items = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            loadError = nil
        } catch {
            // 실패가 빈 상태로 위장하지 않게 — 이미 보이던 목록은 보존한다.
            if items.isEmpty { loadError = error.localizedDescription }
        }
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, let cursor = nextCursor else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let page = try? await NotificationsAPI.list(before: cursor) {
            items += page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        }
    }
}
