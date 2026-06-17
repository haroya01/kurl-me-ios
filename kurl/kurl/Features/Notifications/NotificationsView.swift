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
    /// refresh 가 in-flight loadMore 의 스테일 응답을 폐기하기 위한 세대 토큰.
    @State private var epoch = 0
    @State private var showLoginSheet = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            if !AuthStore.shared.isSignedIn {
                // 알림은 인증 피드 — 비로그인은 네트워크 에러가 아니라 로그인 게이트로(막다른 길 금지).
                loggedOutGate
            } else if loading {
                KurlLoadingMark()
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
        .task(id: AuthStore.shared.isSignedIn) { await load() }
        .refreshable { await load() }
        .sensoryFeedback(.success, trigger: markAllPulse)
    }

    // 비로그인 게이트 — 알림은 인증 피드라, 로그인하면 흐른다고 안내(발견·피드 로그아웃 결과와 동일 문법).
    private var loggedOutGate: some View {
        FeedPlaceholder(
            eyebrow: "알림",
            title: "내 알림을 받으려면",
            message: "로그인하면 좋아요·댓글·팔로우·새 글 알림이 여기에 모여요.",
            actionTitle: "로그인",
            prominent: true,
            action: { showLoginSheet = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
        .loginPrompt(isPresented: $showLoginSheet, message: "내 알림 받기")
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
            KurlLoadingMark()
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
                    .typeScale(.body)
                    // 안 읽은 줄만 한 단계 굵게 — 눈이 그쪽으로 가게(읽은 줄은 §body 기본 regular).
                    .fontWeight(n.read ? .regular : .medium)
                    // 읽은 알림은 한 톤 가라앉혀 — 안 읽은 줄로 눈이 가게.
                    .foregroundStyle(n.read ? Palette.secondary : Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = n.postTitle ?? n.seriesTitle {
                    Text(subtitle)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                if let date = n.createdAt {
                    Text(date.relativeShort)
                        .typeScale(.meta)
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
        // 낙관적으로 점을 끄되, 서버 실패 시 그 줄만 되돌린다 — 거짓 성공을 만들지 않는다.
        guard let idx = items.firstIndex(where: { $0.id == n.id }) else { return }
        let snapshot = items[idx]
        items[idx] = asRead(snapshot)
        Task {
            do {
                try await NotificationsAPI.markRead(id: n.id)
            } catch {
                if let cur = items.firstIndex(where: { $0.id == n.id }) {
                    items[cur] = snapshot
                }
                ToastCenter.shared.show(String(localized: "읽음 처리하지 못했습니다"))
            }
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
        // 비로그인이면 인증 엔드포인트를 때리지 않는다 — 401→영구 재시도 데드엔드 방지(게이트가 화면을 맡는다).
        guard AuthStore.shared.isSignedIn else {
            items = []
            loadError = nil
            loading = false
            return
        }
        epoch += 1
        let myEpoch = epoch
        do {
            let page = try await NotificationsAPI.list()
            guard myEpoch == epoch else { return }
            items = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            loadError = nil
        } catch {
            guard myEpoch == epoch else { return }
            // 실패가 빈 상태로 위장하지 않게 — 이미 보이던 목록은 보존한다.
            if items.isEmpty { loadError = error.localizedDescription }
        }
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, let cursor = nextCursor else { return }
        loadingMore = true
        defer { loadingMore = false }
        let myEpoch = epoch
        if let page = try? await NotificationsAPI.list(before: cursor) {
            // refresh 가 끼어들었으면 이 응답은 옛 세대 — 버린다(append 도 커서 갱신도 없음).
            guard myEpoch == epoch else { return }
            items += page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        }
    }
}
