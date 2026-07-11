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
    /// 마지막 load 시점의 로그인 상태 — 행 push 후 pop-back 이 .task 를 재시작해도
    /// 같은 상태면 재fetch 하지 않아 쌓인 페이지·스크롤 위치를 보존한다.
    @State private var loadedForSignIn: Bool?
    @State private var showLoginSheet = false
    /// 헤드라인 본문 크기 — 작가 이름만 굵게 얹되 Dynamic Type 를 따른다(§body 15.5).
    @ScaledMetric(relativeTo: .callout) private var headlineSize: CGFloat = 15.5
    /// "모두 읽음" 툴바 액션 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var actionSize: CGFloat = 13

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
                // 막다른 길 금지 — 알림은 사람을 팔로우하고 반응하면 흐른다. 발견으로 이어준다
                // (다른 빈 면과 같은 언어 = FeedPlaceholder).
                FeedPlaceholder(
                    eyebrow: "알림",
                    title: "아직 알림이 없어요",
                    message: "팔로우한 작가의 새 글·좋아요·댓글 소식이 여기 모여요.",
                    actionTitle: "발견에서 작가 찾기",
                    action: { TabRouter.shared.selection = 1 }
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
            } else {
                list
            }
        }
        .navigationTitle("알림")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // 목록이 있고 안 읽은 게 있으면 실행 버튼, 모두 읽었으면 흐린 회색 대신
                // 체크마크로 "이미 다 읽음"을 분명히 표시한다(비활성이 안 보이던 문제).
                if !items.isEmpty {
                    if items.allSatisfy(\.read) {
                        Label("모두 읽음", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: actionSize))
                            .foregroundStyle(Palette.secondary)
                            .accessibilityLabel(Text("모두 읽음 상태"))
                    } else {
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
                                    ToastCenter.shared.show(String(localized: "읽음으로 바꾸지 못했어요"))
                                }
                            }
                        }
                        .font(.system(size: actionSize))
                    }
                }
            }
        }
        .task(id: AuthStore.shared.isSignedIn) {
            // 로그인 상태가 바뀌었을 때만 자동 로드 — pop-back 재시작은 통과시킨다.
            // 명시적 갱신은 refreshable·다시 시도 버튼이 맡는다.
            let signedIn = AuthStore.shared.isSignedIn
            guard loadedForSignIn != signedIn else { return }
            loadedForSignIn = signedIn
            await load()
        }
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
            notificationRow(notification)
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

    /// 알림 한 줄 — 아바타는 행위자 프로필로 가는 섬(행 대상과 별개), 본문은 알림 대상(글/시리즈/작가)으로.
    /// 좋아요·댓글 알림에서 좋아요 누른 사람을 눌러도 글이 아니라 그 사람에게 간다(중첩 앵커 대신 형제 링크).
    @ViewBuilder
    private func notificationRow(_ n: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let actor = n.actorUsername, !actor.isEmpty {
                NavigationLink(value: Route.author(username: actor)) {
                    avatarBadge(n)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { markRead(n) })
                .accessibilityLabel(Text("\(actor) 프로필"))
            } else {
                avatarBadge(n)
            }
            Group {
                if let route = route(for: n) {
                    NavigationLink(value: route) {
                        content(n)
                    }
                    .buttonStyle(RowButtonStyle())
                    .simultaneousGesture(TapGesture().onEnded { markRead(n) })
                } else {
                    content(n)
                        .onTapGesture { markRead(n) }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(n.read ? Text(verbatim: "") : Text("읽지 않음"))
        }
        .padding(.vertical, 11)
    }

    // 아바타 = 피드와 같은 문법(0.5px 링). 미읽음은 아바타 우하단의 그린 점 하나로 —
    // 왼쪽 점 칸을 없애 행이 조여지고, 초록은 행당 한 점만(§10 색 규율).
    // 좌하단엔 알림 종류(좋아요·댓글·팔로우…)를 중립 회색 심볼 배지로 얹어, 행마다
    // 똑같아 보이던 아바타 목록에서 종류를 한눈에 훑게 한다 — 초록은 미읽음에만 남긴다.
    private func avatarBadge(_ n: AppNotification) -> some View {
        AvatarView(
            author: Author(
                id: 0, username: n.actorUsername ?? "?", bio: nil, avatarUrl: n.actorAvatarUrl),
            size: 38)
            .overlay(alignment: .bottomLeading) {
                Image(systemName: typeIcon(n.type))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 15, height: 15)
                    .background(Palette.chipBg, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.readingBg, lineWidth: 1.5))
                    .offset(x: -2, y: 2)
            }
            .overlay(alignment: .bottomTrailing) {
                if !n.read {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Palette.readingBg, lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
            }
            .accessibilityHidden(true)
    }

    /// 알림 종류 → 조용한 SF 심볼. 헤드라인 문장과 짝이 맞는 중립 글리프(§10: 색 없이 형태로만).
    private func typeIcon(_ type: String) -> String {
        switch type {
        case "LIKE": return "heart.fill"
        case "COMMENT": return "bubble.left.fill"
        case "REPLY": return "arrowshape.turn.up.left.fill"
        case "FOLLOW": return "person.fill.badge.plus"
        case "SERIES_SUBSCRIBE": return "books.vertical.fill"
        case "NEW_POST": return "doc.text.fill"
        case "MENTION": return "at"
        default: return "bell.fill"
        }
    }

    private func content(_ n: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // 한 줄에 문장 + 오른쪽 끝 상대시간(행마다 시간이 한 열로 정렬돼 훑기 쉽게).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                headline(n)
                    .font(.system(size: headlineSize))
                    .tracking(-0.1)
                    // 읽은 알림은 한 톤 가라앉혀 — 안 읽은 줄로 눈이 가게. 이름은 이미 semibold.
                    .foregroundStyle(n.read ? Palette.secondary : Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let date = n.createdAt {
                    Text(date.relativeShort)
                        .typeScale(.footnote)
                        .foregroundStyle(Palette.faint)
                        .fixedSize()
                }
            }
            if let subtitle = n.postTitle ?? n.seriesTitle {
                Text(subtitle)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    /// 헤드라인 — 작가 이름만 semibold 로 얹어 위계를 세운다(색·크기는 호출측). 지역화 키는
    /// 이름을 Text 로 끼워도 "%@…" 그대로라 ko/ja 번역이 유지된다.
    private func headline(_ n: AppNotification) -> Text {
        let actor = Text(n.actorUsername ?? String(localized: "알 수 없는 사용자"))
            .fontWeight(.semibold)
        switch n.type {
        case "LIKE": return Text("\(actor)님이 글을 좋아해요")
        case "COMMENT": return Text("\(actor)님이 댓글을 남겼어요")
        case "REPLY": return Text("\(actor)님이 답글을 남겼어요")
        case "FOLLOW": return Text("\(actor)님이 팔로우했어요")
        case "SERIES_SUBSCRIBE": return Text("\(actor)님이 시리즈를 구독했어요")
        case "NEW_POST": return Text("\(actor)님이 새 글을 올렸어요")
        case "MENTION": return Text("\(actor)님이 나를 언급했어요")
        default: return actor
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
                ToastCenter.shared.show(String(localized: "읽음으로 바꾸지 못했어요"))
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
