//
//  RemoteSearch.swift
//  kurl
//

import SwiftUI

enum RemoteLookup: Equatable {
    case off
    case looking
    case done(RemoteResolution)

    var isVisible: Bool {
        switch self {
        case .off, .done(.hidden): false
        default: true
        }
    }
}

enum RemoteSearchHint {
    enum Place {
        case peopleTab
        case postsPeopleRail
    }

    static func shows(in place: Place, query: String, remote: [RemoteAccount]?, localPeople: Int) -> Bool {
        guard let remote, remote.isEmpty, FederationAPI.queryDomain(query) == nil,
              FederationAPI.remoteSearchQuery(query).count >= FederationAPI.remoteSearchMinQuery
        else { return false }
        switch place {
        case .peopleTab: return true
        case .postsPeopleRail: return localPeople > 0
        }
    }
}

struct RemoteSearchHintLine: View {
    var body: some View {
        Text("다른 서버 사람은 @아이디@서버 주소로 찾을 수 있어요")
            .typeScale(.meta)
            .foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("search.remote.hint")
    }
}

struct RemoteResolveSlot: View {
    @Binding var lookup: RemoteLookup
    let onSignedIn: () async -> Void
    @State private var showLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("다른 서버")
                .padding(.top, 14)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.remote")
        .loginPrompt(
            isPresented: $showLogin, message: "다른 서버 사람 찾기는 로그인하면 돼요", onSignedIn: onSignedIn)
    }

    @ViewBuilder private var content: some View {
        switch lookup {
        case .looking:
            status("그 서버에 묻는 중…")
        case .done(.account):
            if let account = accountBinding {
                RemoteAccountRow(account: account)
            }
        case .done(.note(let note)):
            NavigationLink(value: Route.note(id: note.id)) {
                QuotedNoteCard(note: QuotedNote(note))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .accessibilityIdentifier("search.remote.note.\(note.id)")
        case .done(.missing(let domain)):
            status("\(domain) 서버에서 찾지 못했어요")
        case .done(.unreachable(let domain)):
            status("\(domain) 서버가 응답하지 않아요")
        case .done(.signIn):
            HStack(spacing: 12) {
                Text("다른 서버 사람 찾기는 로그인하면 돼요")
                    .typeScale(.body)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ToggleCapsuleButton(isOn: false, on: "로그인", off: "로그인", prominent: true, expandTap: 6) {
                    showLogin = true
                }
                .accessibilityIdentifier("search.remote.signIn")
            }
            .padding(.vertical, 12)
        case .off, .done(.hidden):
            EmptyView()
        }
    }

    private func status(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .typeScale(.body)
            .foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .accessibilityIdentifier("search.remote.status")
    }

    private var accountBinding: Binding<RemoteAccount>? {
        guard case .done(.account(let found)) = lookup else { return nil }
        return Binding(
            get: {
                if case .done(.account(let current)) = lookup { return current }
                return found
            },
            set: { lookup = .done(.account($0)) })
    }
}

struct RemotePeopleSection: View {
    @Binding var accounts: [RemoteAccount]
    let divided: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if divided {
                Hairline()
                    .padding(.top, 8)
            }
            if accounts.isEmpty {
                RemoteSearchHintLine()
                    .padding(.top, 18)
            } else {
                RailHeading("다른 서버")
                    .padding(.top, divided ? 20 : 16)
                    .padding(.bottom, 2)
                ForEach($accounts) { $account in
                    RemoteAccountRow(account: $account, roomy: true)
                        .rowDivider(account.id != accounts.first?.id)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.remote.people")
    }
}
