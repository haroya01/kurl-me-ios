//
//  RoomSettingsView.swift
//  kurl
//

import SwiftUI

struct RoomSettingsView: View {
    let onChange: (RoomDetail) -> Void

    @State private var detail: RoomDetail
    @State private var invites: [RoomInvite] = []
    @State private var requests: [RoomJoinRequest] = []
    @State private var invitees: [RoomInvitee] = []
    @State private var hidden: Bool
    @State private var leaving = false
    @State private var removing: RoomDetail.Member?
    @Environment(\.dismiss) private var dismiss

    init(detail: RoomDetail, onChange: @escaping (RoomDetail) -> Void) {
        self.onChange = onChange
        _detail = State(initialValue: detail)
        _hidden = State(initialValue: detail.hiddenFromFeed)
    }

    var body: some View {
        Form {
            if detail.isOwner, !requests.isEmpty {
                Section("들어오고 싶어 해요") {
                    ForEach(requests) { request in
                        HStack(spacing: 10) {
                            AvatarView(author: request.person.author, size: 30)
                            Text(request.person.displayName ?? request.person.username)
                            Spacer()
                            Button("거절") { Task { await decide(request, approve: false) } }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Palette.secondary)
                            Button("승인") { Task { await decide(request, approve: true) } }
                                .buttonStyle(.borderless)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            Section("멤버 \(detail.memberCount)명") {
                ForEach(detail.members) { member in
                    HStack(spacing: 10) {
                        AvatarView(author: member.author, size: 30)
                        Text(member.displayName ?? member.username)
                        if member.role == "OWNER" {
                            Text("방장")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .swipeActions {
                        if detail.isOwner, member.role != "OWNER" {
                            Button("내보내기", role: .destructive) { removing = member }
                        }
                    }
                }
            }
            if !invitees.isEmpty {
                Section("초대에 답을 기다려요") {
                    ForEach(invitees) { invitee in
                        HStack(spacing: 10) {
                            AvatarView(author: invitee.person.author, size: 30)
                            Text(invitee.person.displayName ?? invitee.person.username)
                        }
                        .swipeActions {
                            if detail.isOwner || invitee.inviterId == AuthStore.shared.me?.id {
                                Button("초대 취소", role: .destructive) { Task { await cancel(invitee) } }
                            }
                        }
                    }
                }
            }
            if detail.isOwner, !invites.isEmpty {
                Section("초대 링크") {
                    ForEach(invites) { invite in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.code).typeScale(.note)
                                Text(invite.maxUses.map { "\(invite.uses)/\($0)" } ?? "\(invite.uses)")
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            if invite.disabled {
                                Text("꺼짐").typeScale(.meta).foregroundStyle(Palette.secondary)
                            } else {
                                Button("끄기") { Task { await disable(invite) } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("내 피드에서 이 방 글 숨기기", isOn: $hidden)
                    .onChange(of: hidden) { _, next in
                        Task { _ = try? await RoomAPI.setHiddenFromFeed(detail.id, hidden: next) }
                    }
            } footer: {
                Text("숨겨도 이 방 안에서는 그대로 보여요.")
            }
            Section {
                Button("방 나가기", role: .destructive) { leaving = true }
            }
        }
        .navigationTitle("방 설정")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("방에서 나갈까요?", isPresented: $leaving) {
            Button("내 글 남기고 나가기", role: .destructive) { Task { await leave(deleting: false) } }
            Button("내 글 지우고 나가기", role: .destructive) { Task { await leave(deleting: true) } }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "내보낼까요?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { member in
            Button("내보내기", role: .destructive) { Task { await remove(member) } }
            Button("취소", role: .cancel) {}
        } message: { member in
            Text("\(member.displayName ?? member.username)님은 이 방의 초대 링크로 다시 들어올 수 없어요.")
        }
    }

    private func load() async {
        invitees = (try? await RoomAPI.invitees(detail.id)) ?? []
        guard detail.isOwner else { return }
        async let loadedInvites = RoomAPI.invites(detail.id)
        async let loadedRequests = RoomAPI.requests(detail.id)
        invites = (try? await loadedInvites) ?? []
        requests = (try? await loadedRequests) ?? []
    }

    private func refresh() async {
        if let next = try? await RoomAPI.detail(detail.id) {
            detail = next
            onChange(next)
        }
    }

    private func decide(_ request: RoomJoinRequest, approve: Bool) async {
        if approve {
            try? await RoomAPI.approve(detail.id, member: request.person.id)
        } else {
            try? await RoomAPI.reject(detail.id, member: request.person.id)
        }
        requests.removeAll { $0.id == request.id }
        await refresh()
    }

    private func cancel(_ invitee: RoomInvitee) async {
        try? await RoomAPI.cancelInvitation(detail.id, person: invitee.id)
        invitees.removeAll { $0.id == invitee.id }
    }

    private func disable(_ invite: RoomInvite) async {
        if let next = try? await RoomAPI.disable(detail.id, invite: invite.id) {
            invites = invites.map { $0.id == next.id ? next : $0 }
        }
    }

    private func remove(_ member: RoomDetail.Member) async {
        try? await RoomAPI.remove(detail.id, member: member.id)
        await refresh()
    }

    private func leave(deleting: Bool) async {
        do {
            try await RoomAPI.leave(detail.id, deleteMyNotes: deleting)
            RoomsRouter.shared.path = NavigationPath()
            RoomsRouter.shared.changed()
        } catch {
            ToastCenter.shared.show(String(localized: "방에서 나가지 못했어요"))
        }
    }
}
