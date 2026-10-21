import SwiftUI

struct RoomSettingsView: View {
    let onChange: (RoomDetail) -> Void

    @State private var detail: RoomDetail
    @State private var invites: [RoomInvite] = []
    @State private var requests: [RoomJoinRequest] = []
    @State private var invitees: [RoomInvitee] = []
    @State private var hidden: Bool
    @State private var name: String
    @State private var approval: Bool
    @State private var saving = false
    @State private var leaving = false
    @State private var removing: RoomDetail.Member?
    @Environment(\.dismiss) private var dismiss

    init(detail: RoomDetail, onChange: @escaping (RoomDetail) -> Void) {
        self.onChange = onChange
        _detail = State(initialValue: detail)
        _hidden = State(initialValue: detail.hiddenFromFeed)
        _name = State(initialValue: detail.name)
        _approval = State(initialValue: detail.approvalRequired)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ReadingColumn(spacing: 0) {
            if detail.isOwner, !requests.isEmpty {
                heading("들어오고 싶어 해요")
                ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                    if index > 0 { Hairline() }
                    personRow(request.person.author, name: request.person.displayName ?? request.person.username) {
                        Button("거절") { Task { await decide(request, approve: false) } }
                            .buttonStyle(.plain)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                        Button {
                            Task { await decide(request, approve: true) }
                        } label: {
                            Text("승인")
                                .typeScale(.meta)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(PaperCapsuleStyle(prominent: true))
                        .accessibilityIdentifier("roomSettings.approve.\(request.id)")
                    }
                }
            }
            if detail.isOwner {
                heading("방 이름")
                HStack(spacing: 10) {
                    TextField("방 이름", text: $name)
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                        .submitLabel(.done)
                        .onSubmit { Task { await rename() } }
                        .accessibilityIdentifier("roomSettings.name")
                    if trimmedName != detail.name {
                        Button("저장") { Task { await rename() } }
                            .buttonStyle(.plain)
                            .typeScale(.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.accent)
                            .disabled(trimmedName.isEmpty || trimmedName.count > 50 || saving)
                            .accessibilityIdentifier("roomSettings.saveName")
                    }
                }
                .padding(.vertical, 13)
                Hairline()
            }
            heading("멤버 \(detail.memberCount)명")
            ForEach(Array(detail.members.enumerated()), id: \.element.id) { index, member in
                if index > 0 { Hairline() }
                personRow(member.author, name: member.displayName ?? member.username) {
                    if member.role == "OWNER" {
                        Text("방장")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    } else if detail.isOwner {
                        Menu {
                            Button("내보내기", systemImage: "person.badge.minus", role: .destructive) { removing = member }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text("\(member.displayName ?? member.username) 관리"))
                    }
                }
            }
            if !invitees.isEmpty {
                heading("초대에 답을 기다려요")
                ForEach(Array(invitees.enumerated()), id: \.element.id) { index, invitee in
                    if index > 0 { Hairline() }
                    personRow(invitee.person.author, name: invitee.person.displayName ?? invitee.person.username) {
                        if detail.isOwner || invitee.inviterId == AuthStore.shared.me?.id {
                            Button("초대 취소") { Task { await cancel(invitee) } }
                                .buttonStyle(.plain)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
            if detail.isOwner {
                heading("들어오는 방식")
                toggleRow(
                    "들어오기 전에 승인", note: "켜면 초대 링크로 와도 방장이 받아 줘야 들어와요.", isOn: $approval
                )
                .onChange(of: approval) { _, next in
                    guard next != detail.approvalRequired else { return }
                    Task { await setApproval(next) }
                }
                .accessibilityIdentifier("roomSettings.approval")
                ForEach(invites) { invite in
                    Hairline()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: invite.code)
                                .typeScale(.body)
                                .monospaced()
                                .foregroundStyle(invite.disabled ? Palette.faint : Palette.ink)
                            Text(invite.maxUses.map { String(localized: "\(invite.uses)/\($0)번 사용") }
                                 ?? String(localized: "\(invite.uses)번 사용"))
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        if invite.disabled {
                            Text("꺼짐").typeScale(.meta).foregroundStyle(Palette.faint)
                        } else {
                            Button("링크 끄기") { Task { await disable(invite) } }
                                .buttonStyle(.plain)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .padding(.vertical, 11)
                }
            }
            heading("내 피드")
            toggleRow("이 방 글 숨기기", note: "홈에서만 숨겨요. 이 방 안에서는 그대로 보여요.", isOn: $hidden)
                .onChange(of: hidden) { _, next in
                    Task { _ = try? await RoomAPI.setHiddenFromFeed(detail.id, hidden: next) }
                }
            Hairline().padding(.top, 20)
            Button {
                leaving = true
            } label: {
                HStack {
                    Text("방 나가기")
                        .typeScale(.body)
                        .foregroundStyle(Palette.danger)
                    Spacer()
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityIdentifier("roomSettings.leave")
            Spacer(minLength: 48)
        }
        .navigationTitle("방 설정")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .task { await load() }
        .alert("방에서 나갈까요?", isPresented: $leaving) {
            Button("내 글 남기고 나가기", role: .destructive) { Task { await leave(deleting: false) } }
            Button("내 글 지우고 나가기", role: .destructive) { Task { await leave(deleting: true) } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("지우면 이 방에 올린 내 노트·블로그 글·댓글이 모두 지워져요.")
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

    private func heading(_ title: LocalizedStringKey) -> some View {
        RailHeading(title)
            .padding(.top, 28)
            .padding(.bottom, 4)
    }

    private func personRow(
        _ author: Author, name: String, @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            AvatarView(author: author, size: 34)
            Text(verbatim: name)
                .typeScale(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 14) { trailing() }
        }
        .padding(.vertical, 9)
    }

    private func toggleRow(_ title: LocalizedStringKey, note: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Text(note)
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .tint(GlassTokens.prominentTint)
        .padding(.vertical, 9)
    }

    private func load() async {
        invitees = (try? await RoomAPI.invitees(detail.id)) ?? []
        guard detail.isOwner else { return }
        async let loadedInvites = RoomAPI.invites(detail.id)
        async let loadedRequests = RoomAPI.requests(detail.id)
        invites = (try? await loadedInvites) ?? []
        requests = (try? await loadedRequests) ?? []
    }

    private func rename() async {
        guard !trimmedName.isEmpty, trimmedName.count <= 50, trimmedName != detail.name else { return }
        saving = true
        defer { saving = false }
        do {
            let next = try await RoomAPI.rename(detail.id, name: trimmedName)
            detail = next
            name = next.name
            onChange(next)
            RoomsRouter.shared.changed()
        } catch {
            ToastCenter.shared.show(String(localized: "이름을 바꾸지 못했어요"))
        }
    }

    private func setApproval(_ on: Bool) async {
        do {
            let next = try await RoomAPI.setApproval(detail.id, on)
            detail = next
            onChange(next)
        } catch {
            approval = detail.approvalRequired
            ToastCenter.shared.show(String(localized: "승인 설정을 바꾸지 못했어요"))
        }
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
