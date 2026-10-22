import SwiftUI

/// 다른 서버 계정의 팔로우 캡슐 — 마스토돈처럼 요청을 보낸 뒤 그 서버가 수락해야 팔로잉이 된다.
struct RemoteFollowButton: View {
    @Binding var account: RemoteAccount
    var outlined = false
    var compact = false
    @State private var busy = false
    @State private var confirmUnfollow = false
    @State private var showLogin = false
    @State private var toggles = 0

    var body: some View {
        capsule
            .disabled(busy)
            .accessibilityIdentifier("remote.follow.\(account.acct)")
            .sensoryFeedback(.impact(weight: .light), trigger: toggles)
            .loginPrompt(isPresented: $showLogin, message: "팔로우하려면 로그인하세요") {
                if let fresh = try? await FederationAPI.account(id: account.id) { account = fresh }
            }
            .alert(
                account.following ? "\(account.acct) 팔로우를 끊을까요?" : "팔로우 요청을 취소할까요?",
                isPresented: $confirmUnfollow
            ) {
                Button(account.following ? "팔로우 끊기" : "요청 취소", role: .destructive) {
                    Task { await set(false) }
                }
                Button("취소", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var capsule: some View {
        let title: LocalizedStringKey = account.following ? "팔로잉" : account.requested ? "요청됨" : "팔로우"
        if compact {
            Button(action: tap) { RowFollowCapsuleLabel(title: title) }
                .buttonStyle(PaperCapsuleStyle(prominent: false))
        } else {
            ToggleCapsuleButton(
                isOn: account.following || account.requested,
                on: account.following ? "팔로잉" : "요청됨",
                off: "팔로우",
                prominent: outlined ? false : nil,
                expandTap: 6,
                action: tap)
        }
    }

    private func tap() {
        if !AuthStore.shared.isSignedIn {
            showLogin = true
        } else if account.following || account.requested {
            confirmUnfollow = true
        } else {
            Task { await set(true) }
        }
    }

    private func set(_ on: Bool) async {
        busy = true
        defer { busy = false }
        let previous = account
        account.requested = on
        account.following = false
        toggles += 1
        do {
            account = try await FederationAPI.setFollowing(on, id: account.id)
        } catch {
            account = previous
            ToastCenter.shared.show(FederationAPI.message(for: error))
        }
    }
}

/// 행 링크는 놓이는 스택의 방식을 따른다 — 값 목적지 스택(검색)은 Route 값, 클로저 링크로 쌓는
/// 스택(설정)은 클로저. 한 스택에 두 방식을 섞으면 값 링크가 죽는다.
struct RemoteAccountRow: View {
    @Binding var account: RemoteAccount
    var linksByValue = true
    var roomy = false
    var inFollowList = false

    var body: some View {
        HStack(spacing: inFollowList ? 11 : 12) {
            Group {
                if linksByValue {
                    NavigationLink(value: Route.remoteAccount(id: account.id)) { label }
                } else {
                    NavigationLink { RemoteAccountView(accountId: account.id) } label: { label }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("remote.row.\(account.acct)")
            RemoteFollowButton(account: $account, outlined: true, compact: inFollowList)
        }
        .padding(.vertical, roomy ? 12 : 10)
    }

    @ViewBuilder
    private var name: some View {
        if inFollowList {
            Text(account.shownName).typeScale(.titleSmall)
        } else {
            Text(account.shownName).typeScale(.body).fontWeight(.semibold)
        }
    }

    private var label: some View {
        HStack(spacing: inFollowList ? 11 : 12) {
            AvatarView(author: account.asAuthor, size: roomy || inFollowList ? 44 : 40)
            VStack(alignment: .leading, spacing: 2) {
                name
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(verbatim: "@\(account.acct)")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}

/// 다른 서버 계정 — 검색에서 @아이디@서버로 찾아 들어온다.
struct RemoteAccountView: View {
    let accountId: Int64
    @State private var account: RemoteAccount?
    @State private var failed = false
    @State private var needsSignIn = false
    @State private var showLogin = false
    @State private var notes: NotesViewModel
    @State private var confirmDomainBlock = false
    @State private var confirmBlock = false
    @State private var muting = false
    @Environment(\.openURL) private var openURL

    init(accountId: Int64) {
        self.accountId = accountId
        _notes = State(initialValue: NotesViewModel(remoteAccount: accountId))
    }

    var body: some View {
        ReadingColumn(spacing: 0) {
            if let account {
                header(account)
                Hairline()
                    .padding(.top, 18)
                if account.isDomainBlocked {
                    FeedPlaceholder(
                        title: "\(account.domain)의 노트와 알림은 보이지 않아요.",
                        actionTitle: "\(account.domain) 차단 해제",
                        actionIdentifier: "remote.domain.unblock",
                        action: { Task { await setDomainBlocked(false) } }
                    )
                    .padding(.top, 24)
                } else if account.isBlocking {
                    FeedPlaceholder(
                        title: "차단한 사용자예요",
                        actionTitle: "차단 해제",
                        actionIdentifier: "remote.unblock",
                        action: { Task { await setBlocking(false) } }
                    )
                    .padding(.top, 24)
                } else {
                    notesList
                }
            } else if needsSignIn {
                FeedPlaceholder(
                    title: "다른 서버 계정을 보려면 로그인하세요",
                    actionTitle: "로그인",
                    actionIdentifier: "remote.signIn",
                    action: { showLogin = true }
                )
                .padding(.top, 24)
            } else if failed {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await load() } })
                    .padding(.top, 60)
            } else {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .loginPrompt(isPresented: $showLogin, message: "다른 서버 계정을 보려면 로그인하세요") {
            await load()
            await notes.reload()
        }
        .reservesTabBarSpace()
        .navigationTitle(account.map { "@\($0.acct)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let account {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if account.offersBlockAndMute {
                            if account.isMuting {
                                Button {
                                    Task { await unmute() }
                                } label: {
                                    Label("뮤트 해제", systemImage: "speaker.wave.2")
                                }
                                .accessibilityIdentifier("remote.unmute")
                            } else {
                                Button { muting = true } label: {
                                    Label("뮤트…", systemImage: "speaker.slash")
                                }
                                .accessibilityIdentifier("remote.mute")
                            }
                            if account.isBlocking {
                                Button {
                                    Task { await setBlocking(false) }
                                } label: {
                                    Label("차단 해제", systemImage: "hand.raised.slash")
                                }
                                .accessibilityIdentifier("remote.menu.unblock")
                            } else {
                                Button(role: .destructive) { confirmBlock = true } label: {
                                    Label("차단", systemImage: "hand.raised")
                                }
                                .accessibilityIdentifier("remote.block")
                            }
                            Divider()
                        }
                        if account.isDomainBlocked {
                            Button("\(account.domain) 차단 해제", systemImage: "hand.raised.slash") {
                                Task { await setDomainBlocked(false) }
                            }
                        } else {
                            Button("\(account.domain) 차단", systemImage: "hand.raised", role: .destructive) {
                                confirmDomainBlock = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("더 보기")
                    .accessibilityIdentifier("remote.more")
                }
            }
        }
        .alert(
            "\(account?.domain ?? "") 전체를 차단할까요?",
            isPresented: $confirmDomainBlock
        ) {
            Button("서버 차단", role: .destructive) { Task { await setDomainBlocked(true) } }
                .accessibilityIdentifier("remote.domain.confirm")
            Button("취소", role: .cancel) {}
        } message: {
            Text("그 서버의 노트와 알림이 보이지 않고, 그 서버 계정 팔로우가 끊기며 그 서버의 팔로워도 빠져요. 한 사람만 문제라면 차단이나 뮤트로 충분해요.")
        }
        .alert("\(account?.acct ?? "") 님을 차단할까요?", isPresented: $confirmBlock) {
            Button("차단", role: .destructive) { Task { await setBlocking(true) } }
                .accessibilityIdentifier("remote.block.confirm")
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 계정의 노트와 알림이 보이지 않고, 서로의 팔로우도 끊겨요.")
        }
        .sheet(isPresented: $muting) {
            if let account {
                MuteSheet(remote: account) { muted in
                    self.account = muted
                    NoteFeedPreferences.shared.mutesChanged()
                }
            }
        }
        .task { await load() }
        .task { await notes.reload() }
        .brandRefreshable {
            await load()
            await notes.reload()
        }
    }

    /// 받은 노트만 보인다 — 팔로우하기 전 글은 그 서버에서 본다(마스토돈도 원격 프로필은 받은 것부터).
    @ViewBuilder
    private var notesList: some View {
        switch notes.phase {
        case .idle, .loading:
            KurlLoadingMark()
                .frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await notes.reload() } })
                .padding(.top, 40)
        case .loaded:
            if notes.items.isEmpty {
                FeedPlaceholder(title: "받은 노트가 없어요")
                    .padding(.top, 24)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteFeedItem(
                            note: note,
                            onChange: { notes.replaced($0) },
                            onDelete: { notes.removed($0) }
                        )
                        .task { await notes.loadMoreIfNeeded(current: note) }
                        if index < notes.items.count - 1 { Hairline().padding(.horizontal, -Metrics.gutter) }
                    }
                    if notes.isLoadingMore {
                        KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
                .environment(\.noteFilterContext, notes.filterContext)
            }
        }
    }

    private func header(_ value: RemoteAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                AvatarView(author: value.asAuthor, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.shownName)
                        .typeScale(.name)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    Text(verbatim: "@\(value.acct)")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: 10) {
                if !value.isDomainBlocked && !value.isBlocking {
                    RemoteFollowButton(
                        account: Binding(get: { account ?? value }, set: { account = $0 }))
                }
                if let url = URL(string: value.url) {
                    Button {
                        openURL(url)
                    } label: {
                        Text("\(value.domain)에서 보기")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !value.isDomainBlocked && !value.isBlocking {
                Text(caption(value))
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(_ value: RemoteAccount) -> LocalizedStringKey {
        if value.following { return "\(value.domain)에 있는 계정이에요. 이 계정의 새 노트가 팔로잉 피드에 와요." }
        if value.requested { return "팔로우를 요청했어요. \(value.domain)이 수락하면 팔로잉이 돼요." }
        return "\(value.domain)에 있는 계정이에요. 팔로우하면 \(value.domain)에 요청을 보내요."
    }

    private func load() async {
        failed = false
        needsSignIn = !AuthStore.shared.isSignedIn
        guard !needsSignIn else { return }
        do {
            account = try await FederationAPI.account(id: accountId)
        } catch {
            needsSignIn = account == nil && FederationAPI.needsSignIn(error)
            failed = account == nil && !needsSignIn
        }
    }

    private func setBlocking(_ on: Bool) async {
        guard let id = account?.id else { return }
        do {
            account = try await FederationAPI.setBlocking(on, id: id)
            NoteFeedPreferences.shared.mutesChanged()
            if !on { await notes.reload() }
            ToastCenter.shared.show(
                on
                    ? String(localized: "차단했어요. 이 계정의 노트가 숨겨져요")
                    : String(localized: "차단을 해제했어요"))
        } catch {
            ToastCenter.shared.show(
                on ? String(localized: "차단하지 못했어요") : String(localized: "해제하지 못했어요"))
        }
    }

    private func unmute() async {
        guard let id = account?.id else { return }
        do {
            account = try await FederationAPI.unmute(id: id)
            NoteFeedPreferences.shared.mutesChanged()
            ToastCenter.shared.show(String(localized: "뮤트를 해제했어요"))
        } catch {
            ToastCenter.shared.show(String(localized: "해제하지 못했어요"))
        }
    }

    private func setDomainBlocked(_ on: Bool) async {
        guard let domain = account?.domain else { return }
        do {
            try await FederationAPI.setDomainBlocked(on, domain: domain)
            await load()
            if !on { await notes.reload() }
            ToastCenter.shared.show(
                on
                    ? String(localized: "\(domain)을 차단했어요")
                    : String(localized: "\(domain) 차단을 해제했어요"))
        } catch {
            ToastCenter.shared.show(FederationAPI.message(for: error))
        }
    }
}

/// 설정 > 안전 — 차단한 서버(마스토돈의 도메인 차단). 그 서버의 노트·알림·팔로우가 모두 빠진다.
struct DomainBlocksView: View {
    @State private var blocks: [DomainBlock] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            Color.clear.frame(height: 8)
            if loading && blocks.isEmpty {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed && blocks.isEmpty {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await load() } })
                    .padding(.top, 60)
            } else if blocks.isEmpty {
                FeedPlaceholder(title: "차단한 서버가 없어요")
                    .padding(.top, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(blocks) { block in
                        row(block)
                        if block.id != blocks.last?.id { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("차단한 서버")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .task { await load() }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            blocks = try await FederationAPI.domainBlocks()
        } catch {
            failed = true
        }
        loading = false
    }

    private func row(_ block: DomainBlock) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: block.domain)
                .typeScale(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("차단 해제") {
                Task {
                    do {
                        try await FederationAPI.setDomainBlocked(false, domain: block.domain)
                        withMotion(Motion.micro) { blocks.removeAll { $0.id == block.id } }
                        ToastCenter.shared.show(String(localized: "\(block.domain) 차단을 해제했어요"))
                    } catch {
                        ToastCenter.shared.show(String(localized: "해제하지 못했어요"))
                    }
                }
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.ink)
            .accessibilityIdentifier("domainBlocks.unblock.\(block.domain)")
        }
        .padding(.vertical, 12)
    }
}

/// 설정 > 노트 연합 — 내가 다른 서버에서 팔로우하는 계정(요청 중 포함).
struct RemoteFollowingView: View {
    @State private var accounts: [RemoteAccount] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            Color.clear.frame(height: 8)
            if loading && accounts.isEmpty {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed && accounts.isEmpty {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await load() } })
                    .padding(.top, 60)
            } else if accounts.isEmpty {
                FeedPlaceholder(title: "다른 서버에서 팔로우하는 계정이 없어요")
                    .padding(.top, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach($accounts) { $account in
                        RemoteAccountRow(account: $account, linksByValue: false)
                        if account.id != accounts.last?.id { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("다른 서버 팔로잉")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .task { await load() }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            accounts = try await FederationAPI.following()
        } catch {
            failed = true
        }
        loading = false
    }
}

struct OtherServerSection<Content: View>: View {
    let divided: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if divided {
                Hairline()
            }
            RailHeading("다른 서버")
                .padding(.top, divided ? 24 : 8)
                .padding(.bottom, 2)
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.remote")
    }
}

struct RemoteSafetyRow: View {
    let account: RemoteAccount
    var mute: RemoteMute?
    let actionTitle: LocalizedStringKey
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(author: account.asAuthor, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.acct)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let mute {
                    Group {
                        if let end = mute.expiresAt {
                            Text("\(end, format: .dateTime.month().day().hour().minute())까지")
                        } else {
                            Text("무기한")
                        }
                    }
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(actionTitle) {
                Task { await action() }
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.ink)
            .accessibilityIdentifier("remote.safety.\(account.acct)")
        }
        .padding(.vertical, 12)
    }
}
