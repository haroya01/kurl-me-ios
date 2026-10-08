//
//  RemoteAccountViews.swift
//  kurl
//

import SwiftUI

/// 다른 서버 계정의 팔로우 캡슐 — 마스토돈처럼 요청을 보낸 뒤 그 서버가 수락해야 팔로잉이 된다.
struct RemoteFollowButton: View {
    @Binding var account: RemoteAccount
    @State private var busy = false
    @State private var confirmUnfollow = false
    @State private var toggles = 0

    var body: some View {
        ToggleCapsuleButton(
            isOn: account.following || account.requested,
            on: account.following ? "팔로잉" : "요청됨",
            off: "팔로우",
            expandTap: 6
        ) {
            if account.following || account.requested {
                confirmUnfollow = true
            } else {
                Task { await set(true) }
            }
        }
        .disabled(busy)
        .accessibilityIdentifier("remote.follow.\(account.acct)")
        .sensoryFeedback(.impact(weight: .light), trigger: toggles)
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

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if linksByValue {
                    NavigationLink(value: Route.remoteAccount(id: account.id)) { label }
                } else {
                    NavigationLink { RemoteAccountView(accountId: account.id) } label: { label }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("remote.row.\(account.acct)")
            RemoteFollowButton(account: $account)
        }
        .padding(.vertical, 10)
    }

    private var label: some View {
        HStack(spacing: 12) {
            AvatarView(author: account.asAuthor, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.shownName)
                    .typeScale(.body)
                    .fontWeight(.semibold)
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
    @State private var notes: NotesViewModel
    @State private var confirmDomainBlock = false
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
                    ContentUnavailableView {
                        Label("차단한 서버예요", systemImage: "hand.raised")
                    } description: {
                        Text("\(account.domain)의 노트와 알림은 보이지 않아요.")
                    } actions: {
                        Button("\(account.domain) 차단 해제") { Task { await setDomainBlocked(false) } }
                            .accessibilityIdentifier("remote.domain.unblock")
                    }
                    .padding(.top, 40)
                } else {
                    notesList
                }
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
        .navigationTitle(account.map { "@\($0.acct)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let account {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
                ContentUnavailableView {
                    Label("받은 노트가 없어요", systemImage: "globe")
                } description: {
                    Text("팔로우하면 이 계정이 쓰는 새 노트가 여기와 팔로잉 피드에 와요.")
                }
                .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
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
                if !value.isDomainBlocked {
                    RemoteFollowButton(
                        account: Binding(get: { account ?? value }, set: { account = $0 }))
                }
                if let url = URL(string: value.url) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("\(value.domain)에서 보기", systemImage: "arrow.up.right.square")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.link)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !value.isDomainBlocked {
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
        do {
            account = try await FederationAPI.account(id: accountId)
        } catch {
            failed = account == nil
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
                ContentUnavailableView {
                    Label("차단한 서버가 없어요", systemImage: "hand.raised")
                } description: {
                    Text("다른 서버 계정 화면의 ⋯ 메뉴에서 그 서버 전체를 차단할 수 있어요.")
                }
                .padding(.top, 60)
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
            Image(systemName: "server.rack")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 36, height: 36)
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
                        withAnimation(.snappy(duration: 0.2)) { blocks.removeAll { $0.id == block.id } }
                        ToastCenter.shared.show(String(localized: "\(block.domain) 차단을 해제했어요"))
                    } catch {
                        ToastCenter.shared.show(String(localized: "해제하지 못했어요"))
                    }
                }
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.link)
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
                ContentUnavailableView {
                    Label("다른 서버에서 팔로우하는 계정이 없어요", systemImage: "globe")
                } description: {
                    Text("검색에 @아이디@서버를 적으면 마스토돈 같은 다른 서버의 계정을 찾을 수 있어요.")
                }
                .padding(.top, 60)
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
