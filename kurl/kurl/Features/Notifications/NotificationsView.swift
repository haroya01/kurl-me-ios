import SwiftUI
import UserNotifications

/// 알림 — 웹 벨과 같은 데이터. 행 탭 = 읽음 처리 + 대상(글/작가/시리즈)으로 이동,
/// 미읽음은 왼쪽 그린 점 하나로 조용히 표시한다.
struct NotificationsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = NotificationsViewModel()
    /// "모두 읽음" 성공 햅틱 트리거 — 글 완독 성공 햅틱과 같은 결의 확인음.
    @State private var markAllPulse = 0
    /// 마지막 load 시점의 로그인 상태 — 행 push 후 pop-back 이 .task 를 재시작해도
    /// 같은 상태면 첫 페이지로 갈아엎지 않아 쌓인 페이지·스크롤 위치를 보존한다.
    @State private var loadedForSignIn: Bool?
    @State private var showLoginSheet = false
    @State private var pushStatus: UNAuthorizationStatus?
    @State private var followRequests = FollowRequestStore.shared
    @State private var filtered = FilteredNotificationStore.shared
    @State private var unread = UnreadStore.shared
    @AppStorage("inboxPushBannerDismissed") private var pushBannerDismissed = false
    @Environment(\.openURL) private var openURL
    /// "모두 읽음" 툴바 액션 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var actionSize: CGFloat = 13

    var body: some View {
        screen
        .reservesTabBarSpace()
        .navigationTitle("알림")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AuthStore.shared.isSignedIn {
                ToolbarItem(placement: .principal) {
                    Picker("알림 보기", selection: $model.filter) {
                        Text("전체").tag(NotificationFilter.all)
                        Text("멘션").tag(NotificationFilter.mentions)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("notifications.filter")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // 목록이 있고 안 읽은 게 있으면 실행 버튼, 모두 읽었으면 흐린 회색 대신
                // 체크마크로 "이미 다 읽음"을 분명히 표시한다(비활성이 안 보이던 문제).
                if !shownItems.isEmpty {
                    if shownItems.allSatisfy(\.read) {
                        Label("모두 읽음", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: actionSize))
                            .foregroundStyle(Palette.secondary)
                            .accessibilityLabel(Text("모두 읽음 상태"))
                    } else {
                        Button("모두 읽음") {
                            Task {
                                do {
                                    try await NotificationsAPI.markAllRead(filter: model.filter)
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        model.items = model.items.map(asRead)
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
            // 로그인 상태가 바뀌었을 때만 처음부터 로드 — pop-back 재시작은 미읽음이 있을 때만 조용히 다시 읽는다.
            let signedIn = AuthStore.shared.isSignedIn
            guard loadedForSignIn != signedIn else {
                await resume()
                return
            }
            loadedForSignIn = signedIn
            await load()
        }
        .refreshable { await load() }
        .onChange(of: model.filter) {
            model.switchedFilter()
            Task { await load() }
        }
        .sensoryFeedback(.selection, trigger: model.filter)
        // 걸러진 알림을 받으면 그 알림이 목록으로 들어온다 — 돌아왔을 때 보이게 다시 읽는다.
        .onChange(of: filtered.acceptedCount) { Task { await load() } }
        .onChange(of: unread.arrival) {
            guard AuthStore.shared.isSignedIn else { return }
            Task { await model.catchUp() }
        }
        .task { await reloadPushStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await reloadPushStatus() }
            Task { await resume() }
        }
        .sensoryFeedback(.success, trigger: markAllPulse)
        .onDisappear {
            // 인박스를 떠나면 미읽음 점을 갱신 — 여기서 읽었는데 계정·피드 벨에 점이 남지 않게.
            // 벨을 값 링크로 밀면서 계정 뷰의 onChange 복귀 갱신이 안 걸리므로 인박스가 스스로 챙긴다.
            if AuthStore.shared.isSignedIn {
                Task { await UnreadStore.shared.refresh() }
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        if !AuthStore.shared.isSignedIn {
            // 알림은 인증 피드 — 비로그인은 네트워크 에러가 아니라 로그인 게이트로(막다른 길 금지).
            ReadingColumn(spacing: 0) { loggedOutGate }
        } else if model.loading {
            ReadingColumn(spacing: 0) {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        } else if model.items.isEmpty, let loadError = model.loadError {
            ReadingColumn(spacing: 0) {
                ErrorState(message: loadError, retry: { Task { await load() } })
                    .padding(.top, 60)
            }
        } else {
            inbox
        }
    }

    private var inbox: some View {
        let shown = shownItems
        let tail = Set(shown.suffix(3).map(\.id))
        return List {
            Section {
                if let pushStatus, !pushBannerDismissed, pushStatus == .notDetermined || pushStatus == .denied {
                    pushBanner(pushStatus)
                        .inboxRow()
                }
                if model.filter == .all {
                    followRequestsEntry
                    filteredEntry
                } else {
                    directEntry
                }
                if shown.isEmpty {
                    emptyPlaceholder
                        .inboxRow()
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(InboxSection.buckets(shown, now: .now, calendar: .current)) { bucket in
                Section {
                    ForEach(bucket.items) { notification in
                        notificationRow(notification)
                            .modifier(NoteArrival(
                                active: model.arrivals.ids.contains(notification.id),
                                moves: !model.arrivals.regrouped.contains(notification.id),
                                gutter: Metrics.gutter,
                                wash: Palette.chipBg))
                            .inboxRow()
                            .task {
                                if tail.contains(notification.id) { await model.loadMore() }
                            }
                    }
                } header: {
                    Text(bucket.section.title)
                }
            }
            if model.loadingMore {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .inboxRow()
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .frame(maxWidth: Metrics.readingColumn)
        .frame(maxWidth: .infinity)
        .background(Palette.pageBg)
    }

    @ViewBuilder
    private var emptyPlaceholder: some View {
        if model.filter == .mentions {
            FeedPlaceholder(
                title: "아직 멘션이나 답글이 없어요",
                actionTitle: "피드 둘러보기",
                action: { TabRouter.shared.selection = TabRouter.homeTab }
            )
            .padding(.top, 24)
        } else {
            // 막다른 길 금지 — 알림은 사람을 팔로우하고 반응하면 흐른다. 검색의 작가 레일로 이어준다
            // (다른 빈 면과 같은 언어 = FeedPlaceholder).
            FeedPlaceholder(
                title: "아직 알림이 없어요",
                actionTitle: "검색에서 작가 찾기",
                action: { TabRouter.shared.selection = TabRouter.exploreTab }
            )
            .padding(.top, 24)
        }
    }

    private func pushBanner(_ status: UNAuthorizationStatus) -> some View {
        HStack(spacing: 10) {
            Text("푸시 알림이 꺼져 있어요")
                .typeScale(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(status == .denied ? "설정 열기" : "켜기") {
                if status == .denied {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } else {
                    Task {
                        _ = await PushRegistrar.requestAndRegister()
                        await reloadPushStatus()
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accentFill)
            .controlSize(.small)
            .accessibilityIdentifier("push-prompt-action")
            Button {
                pushBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("닫기"))
            .accessibilityIdentifier("push-prompt-dismiss")
        }
        .padding(.vertical, 6)
    }

    private func reloadPushStatus() async {
        pushStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // 비로그인 게이트 — 알림은 인증 피드라, 로그인하면 흐른다고 안내(발견·피드 로그아웃 결과와 동일 문법).
    private var loggedOutGate: some View {
        FeedPlaceholder(
            title: "로그인하면 좋아요·댓글·팔로우·새 글 알림이 여기에 모여요.",
            actionTitle: "로그인",
            action: { showLoginSheet = true }
        )
        .padding(.top, 24)
        .loginPrompt(isPresented: $showLoginSheet, message: "알림을 보려면 로그인하세요")
    }

    private var shownItems: [AppNotification] {
        model.items.filter { !NotificationsViewModel.hiddenByFilter($0) }
    }

    @ViewBuilder
    private var followRequestsEntry: some View {
        let waiting = followRequests.requests
        if !waiting.isEmpty {
            NavigationLink(value: Route.followRequests) {
                entryLabel("팔로우 요청", symbol: "person.badge.clock") {
                    Text(verbatim: "\(waiting.count)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .accessibilityIdentifier("notifications.followRequests")
            .inboxRow()
        }
    }

    private var directEntry: some View {
        NavigationLink(value: Route.noteFeed(.kind(.direct))) {
            entryLabel("개인 멘션", symbol: NoteFeedKind.direct.symbol) { EmptyView() }
        }
        .accessibilityIdentifier("notifications.direct")
        .inboxRow()
    }

    @ViewBuilder
    private var filteredEntry: some View {
        let senders = filtered.senders
        if !senders.isEmpty {
            NavigationLink(value: Route.filteredNotifications) {
                entryLabel("걸러진 알림", symbol: "line.3.horizontal.decrease") {
                    Text("\(senders.count)명이 보낸 알림 \(senders.reduce(0) { $0 + $1.count })개")
                }
            }
            .accessibilityIdentifier("notifications.filtered")
            .inboxRow()
        }
    }

    private func entryLabel<Trailing: View>(
        _ title: LocalizedStringKey, symbol: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .typeScale(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    /// 알림 한 줄 — 아바타는 행위자 프로필로 가는 섬(행 대상과 별개), 본문은 알림 대상(글/시리즈/작가)으로.
    /// 좋아요·댓글 알림에서 좋아요 누른 사람을 눌러도 글이 아니라 그 사람에게 간다(중첩 앵커 대신 형제 링크).
    private func notificationRow(_ n: AppNotification) -> some View {
        let row = InboxRow(n, me: AuthStore.shared.me?.username)
        return HStack(alignment: .top, spacing: 10) {
            kindGlyph(row, unread: !n.read)
            avatarLink(n, row)
                .fixedSize()
            VStack(alignment: .leading, spacing: 8) {
                rowBody(n, row)
                if n.type == "FOLLOW_REQUEST", let origin = requestOrigin(n) {
                    AnswerButtons(origin: origin, name: n.actorUsername ?? "") {
                        model.items.removeAll { $0.id == n.id }
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .navigationLinkIndicatorVisibility(.hidden)
    }

    private func kindGlyph(_ row: InboxRow, unread: Bool) -> some View {
        Group {
            if row.name == nil {
                Text(verbatim: " ")
            } else {
                Text(Image(systemName: row.symbol))
            }
        }
        .typeScale(.body)
        .foregroundStyle(Palette.secondary)
        .frame(width: 18)
        .overlay(alignment: .leading) {
            if unread {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 8, height: 8)
                    .offset(x: -14)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func avatarLink(_ n: AppNotification, _ row: InboxRow) -> some View {
        if row.name == nil {
            Image(systemName: row.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 38, height: 38)
                .background(Palette.chipBg, in: Circle())
                .accessibilityHidden(true)
        } else if let remoteId = n.actorRemoteId {
            NavigationLink(value: Route.remoteAccount(id: remoteId)) {
                avatar(n)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { markRead(n) })
            .accessibilityLabel(Text("\(n.actorUsername ?? "") 프로필"))
        } else if let remote = n.actorProfileUrl.flatMap(URL.init(string:)) {
            Link(destination: remote) {
                avatar(n)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { markRead(n) })
            .accessibilityLabel(Text("\(n.actorUsername ?? "") 프로필"))
        } else if let actor = n.actorUsername, !actor.isEmpty {
            NavigationLink(value: Route.author(username: actor)) {
                avatar(n)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { markRead(n) })
            .accessibilityLabel(Text("\(actor) 프로필"))
        } else {
            avatar(n)
        }
    }

    private func avatar(_ n: AppNotification) -> some View {
        AvatarView(
            author: Author(id: 0, username: n.actorUsername ?? "", bio: nil, avatarUrl: n.actorAvatarUrl),
            size: 38)
            .accessibilityHidden(true)
    }

    private func rowBody(_ n: AppNotification, _ row: InboxRow) -> some View {
        Group {
            if n.type == "FOLLOW_REQUEST" {
                NavigationLink(value: Route.followRequests) {
                    rowText(n, row)
                }
                .buttonStyle(RowButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { markRead(n) })
            } else if n.type == "REMOTE_FOLLOW", let remoteId = n.actorRemoteId {
                NavigationLink(value: Route.remoteAccount(id: remoteId)) {
                    rowText(n, row)
                }
                .buttonStyle(RowButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { markRead(n) })
            } else if let route = NotificationRoute.route(for: n) {
                NavigationLink(value: route) {
                    rowText(n, row)
                }
                .buttonStyle(RowButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { markRead(n) })
            } else if n.type == "REMOTE_FOLLOW", let remote = n.actorProfileUrl.flatMap(URL.init(string:)) {
                Link(destination: remote) {
                    rowText(n, row)
                }
                .buttonStyle(RowButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { markRead(n) })
            } else {
                rowText(n, row)
                    .onTapGesture { markRead(n) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel(n))
        .accessibilityValue(n.read ? Text(verbatim: "") : Text("읽지 않음"))
    }

    private func rowText(_ n: AppNotification, _ row: InboxRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title(row, unread: !n.read)
                Spacer(minLength: 4)
                if let date = n.createdAt, !dynamicTypeSize.isAccessibilitySize {
                    Text(date.relativeShort)
                        .typeScale(.footnote)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize()
                }
            }
            if let date = n.createdAt, dynamicTypeSize.isAccessibilitySize {
                Text(date.relativeShort)
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
            switch row.detail {
            case .theirs(let text):
                Text(verbatim: text)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
            case .mine(let target, let text):
                HStack(spacing: 0) {
                    Text(target.label)
                        .layoutPriority(1)
                    Text(verbatim: " · \(text)")
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func title(_ row: InboxRow, unread: Bool) -> some View {
        let weight: Font.Weight = unread ? .semibold : .regular
        if let name = row.name {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                EmojiText(
                    row.others > 0 ? AttributedString(localized: "\(name) 외 \(row.others)명") : AttributedString(name),
                    emojis: row.emojis)
                .fontWeight(weight)
                .foregroundStyle(Palette.ink)
                .layoutPriority(1)
                if let label = row.kind.label {
                    Text(label)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .typeScale(.body)
            .lineLimit(1)
        } else if let label = row.kind.label {
            Text(label)
                .typeScale(.body)
                .fontWeight(weight)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
    }

    private func spokenLabel(_ n: AppNotification) -> Text {
        let rest = [subtitle(n), n.createdAt?.relativeShort]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return rest.isEmpty ? headline(n) : Text("\(headline(n)), \(rest)")
    }

    /// 헤드라인 — 작가 이름만 semibold 로 얹어 위계를 세운다(색·크기는 호출측). 지역화 키는
    /// 이름을 Text 로 끼워도 "%@…" 그대로라 ko/ja 번역이 유지된다.
    private func headline(_ n: AppNotification) -> Text {
        let actor = Text(n.actorUsername ?? String(localized: "알 수 없는 사용자"))
            .fontWeight(.semibold)
        switch n.type {
        case "LIKE":
            let others = max((n.count ?? 1) - 1, 0)
            return others > 0
                ? Text("\(actor)님 외 \(others)명이 글을 좋아해요")
                : Text("\(actor)님이 글을 좋아해요")
        case "COMMENT_LIKE":
            let others = max((n.count ?? 1) - 1, 0)
            // 서버는 하이라이트 답글 좋아요도 COMMENT_LIKE 로 보낸다 — commentId 없이 highlightId 만 온다.
            if n.commentId == nil, n.highlightId != nil {
                return others > 0
                    ? Text("\(actor)님 외 \(others)명이 하이라이트에 단 내 답글을 좋아해요")
                    : Text("\(actor)님이 하이라이트에 단 내 답글을 좋아해요")
            }
            return others > 0
                ? Text("\(actor)님 외 \(others)명이 내 댓글을 좋아해요")
                : Text("\(actor)님이 내 댓글을 좋아해요")
        case "HIGHLIGHT":
            let others = max((n.count ?? 1) - 1, 0)
            return others > 0
                ? Text("\(actor)님 외 \(others)명이 내 글에 하이라이트를 남겼어요")
                : Text("\(actor)님이 내 글에 하이라이트를 남겼어요")
        case "POST_QUOTE": return Text("\(actor)님이 노트에서 내 글을 인용했어요")
        case "NOTE_EMBED": return Text("\(actor)님이 글에서 내 노트를 인용했어요")
        case "COMMENT": return Text("\(actor)님이 댓글을 남겼어요")
        case "REPLY": return Text("\(actor)님이 답글을 남겼어요")
        case "FOLLOW": return Text("\(actor)님이 팔로우했어요")
        case "SERIES_SUBSCRIBE": return Text("\(actor)님이 시리즈를 구독했어요")
        case "NEW_POST": return Text("\(actor)님이 새 글을 올렸어요")
        case "MENTION": return Text("\(actor)님이 나를 언급했어요")
        // 연결 그래프 — 컬렉션 이름은 본문 톤으로 얹고 작가 이름만 semibold(위계는 한 겹).
        case "CONNECTED":
            let name = n.collectionName ?? String(localized: "컬렉션")
            return Text("\(actor)님이 회원님의 글을 ‘\(name)’에 엮었어요")
        case "PATH_GREW":
            let name = n.collectionName ?? String(localized: "컬렉션")
            return Text("회원님이 엮인 ‘\(name)’에 새 글이 이어졌어요")
        case "NOTE_LIKE":
            let others = max((n.count ?? 1) - 1, 0)
            return others > 0
                ? Text("\(actor)님 외 \(others)명이 내 노트를 좋아해요")
                : Text("\(actor)님이 내 노트를 좋아해요")
        case "NOTE_REPOST":
            let others = max((n.count ?? 1) - 1, 0)
            return others > 0
                ? Text("\(actor)님 외 \(others)명이 내 노트를 리포스트했어요")
                : Text("\(actor)님이 내 노트를 리포스트했어요")
        case "NOTE_REPLY": return Text("\(actor)님이 내 노트에 답글을 남겼어요")
        case "NOTE_QUOTE": return Text("\(actor)님이 내 노트를 인용했어요")
        case "NOTE_MENTION": return Text("\(actor)님이 노트에서 나를 언급했어요")
        case "NOTE_POLL":
            return n.actorUsername != nil && n.actorUsername == AuthStore.shared.me?.username
                ? Text("내 투표가 끝났어요")
                : Text("\(actor)님의 투표가 끝났어요")
        case "NOTE_POST": return Text("\(actor)님이 새 노트를 올렸어요")
        case "NOTE_EDIT": return Text("\(actor)님이 내가 리포스트하거나 인용한 노트를 수정했어요")
        case "REMOTE_FOLLOW": return Text("\(actor)님이 다른 서버에서 나를 팔로우했어요")
        case "FOLLOW_REQUEST": return Text("\(actor)님이 팔로우를 요청했어요")
        case "POST_FIRST_READER": return Text("첫 독자가 생겼어요")
        case "POST_READ_MILESTONE":
            guard let milestone = n.milestone else { return Text("읽은 사람이 늘었어요") }
            return Text("\(milestone.formatted())명이 읽었어요")
        default: return actor
        }
    }

    private func subtitle(_ n: AppNotification) -> String? {
        switch n.type {
        case "NOTE_REPLY", "NOTE_QUOTE": return n.sourceExcerpt
        case "NOTE_LIKE", "NOTE_REPOST", "NOTE_MENTION", "NOTE_POLL", "NOTE_POST", "NOTE_EDIT",
            "POST_QUOTE":
            return n.noteExcerpt
        default: return n.postTitle ?? n.seriesTitle
        }
    }

    private func requestOrigin(_ n: AppNotification) -> FollowRequest.Origin? {
        if let remoteId = n.actorRemoteId { return .remote(id: remoteId) }
        if let username = n.actorUsername, !username.isEmpty { return .member(username: username) }
        return nil
    }

    private func markRead(_ n: AppNotification) {
        guard !n.read else { return }
        // 낙관적으로 점을 끄되, 서버 실패 시 그 줄만 되돌린다 — 거짓 성공을 만들지 않는다.
        guard let idx = model.items.firstIndex(where: { $0.id == n.id }) else { return }
        let snapshot = model.items[idx]
        model.items[idx] = asRead(snapshot)
        Task {
            do {
                try await NotificationsAPI.markRead(id: n.id)
            } catch {
                if let cur = model.items.firstIndex(where: { $0.id == n.id }) {
                    model.items[cur] = snapshot
                }
                ToastCenter.shared.show(String(localized: "읽음으로 바꾸지 못했어요"))
            }
        }
    }

    private func asRead(_ n: AppNotification) -> AppNotification {
        var read = n
        read.read = true
        return read
    }

    private func load() async {
        // 비로그인이면 인증 엔드포인트를 때리지 않는다 — 401→영구 재시도 데드엔드 방지(게이트가 화면을 맡는다).
        guard AuthStore.shared.isSignedIn else {
            model.signedOut()
            followRequests.reset()
            filtered.reset()
            return
        }
        await model.load()
    }

    private func resume() async {
        guard AuthStore.shared.isSignedIn else { return }
        await unread.refresh()
        await model.resume(unread: unread.count)
    }
}

private extension View {
    func inboxRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Metrics.gutter, bottom: 0, trailing: Metrics.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Palette.hairline)
    }
}
