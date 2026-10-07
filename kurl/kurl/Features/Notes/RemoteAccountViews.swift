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
    @Environment(\.openURL) private var openURL

    var body: some View {
        ReadingColumn(spacing: 0) {
            if let account {
                header(account)
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
        .task { await load() }
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
                RemoteFollowButton(
                    account: Binding(get: { account ?? value }, set: { account = $0 }))
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
            Text(caption(value))
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
