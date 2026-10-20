//
//  RoomInviteSheet.swift
//  kurl
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct RoomInviteSheet: View {
    let roomId: Int64
    let roomName: String
    var memberIds: Set<Int64> = []
    var preselected: [RoomPerson] = []

    enum Source: String, CaseIterable, Identifiable {
        case following, followers
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .following ? "팔로잉" : "팔로워" }
    }

    struct Candidate: Hashable, Identifiable {
        let id: Int64
        let username: String
        let displayName: String?
        let avatarUrl: String?

        var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? username }
        var author: Author {
            Author(id: id, username: username, bio: nil, avatarUrl: avatarUrl, displayName: displayName)
        }
    }

    @State private var source: Source = .following
    @State private var query = ""
    @State private var lists: [Source: [Candidate]] = [:]
    @State private var matches: [Candidate] = []
    @State private var searching = false
    @State private var picked: [Candidate] = []
    @State private var invited: Set<Int64> = []
    @State private var sending = false
    @State private var failed: String?
    @State private var invite: RoomInvite?
    @State private var showsLink = false
    @State private var copied = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0, background: Palette.readingBg) {
                linkActions
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                if !picked.isEmpty {
                    pickedStrip
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if PeopleAPI.isSearchable(query) {
                    rows(matches, empty: searching ? nil : "찾는 사람이 없어요")
                } else {
                    ContentTabBar(
                        tabs: Source.allCases, selection: $source, label: \.title,
                        identifier: { "roomInvite.tab.\($0.rawValue)" },
                        background: Palette.readingBg)
                        .padding(.bottom, 4)
                    if let list = lists[source] {
                        rows(list, empty: source == .following ? "아직 팔로우하는 사람이 없어요" : "아직 팔로워가 없어요")
                    } else {
                        KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: picked)
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("이름이나 아이디로 찾기"))
            .navigationTitle("초대하기")
            .navigationSubtitle(roomName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView()
                        } else if picked.isEmpty {
                            Text("초대")
                        } else {
                            Text("\(picked.count)명 초대")
                        }
                    }
                    .disabled(picked.isEmpty || sending)
                    .accessibilityIdentifier("roomInvite.send")
                }
            }
            .task { await loadInvited() }
            .task { await loadLink() }
            .task(id: source) { await loadList(source) }
            .task(id: query) { await search() }
            .sheet(isPresented: $showsLink) {
                if let invite {
                    RoomLinkSheet(roomId: roomId, roomName: roomName, invite: invite) { self.invite = $0 }
                }
            }
            .alert(
                "초대를 보내지 못했어요",
                isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(failed ?? "")
            }
            .sensoryFeedback(.success, trigger: copied)
        }
        .onAppear {
            if picked.isEmpty {
                picked = preselected
                    .filter { !memberIds.contains($0.id) }
                    .map { Candidate(id: $0.id, username: $0.username, displayName: $0.displayName, avatarUrl: $0.avatarUrl) }
            }
        }
    }

    private var linkActions: some View {
        HStack(spacing: 8) {
            Button {
                guard let url = invite?.shareURL else { return }
                UIPasteboard.general.url = url
                copied += 1
                ToastCenter.shared.show(String(localized: "초대 링크를 복사했어요"))
            } label: {
                linkLabel("링크 복사", systemImage: "link")
            }
            .buttonStyle(PaperCapsuleStyle(prominent: false))
            .accessibilityIdentifier("roomInvite.copy")
            if let url = invite?.shareURL {
                ShareLink(item: url, subject: Text(roomName)) {
                    linkLabel("공유", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PaperCapsuleStyle(prominent: false))
                .accessibilityIdentifier("roomInvite.share")
            } else {
                Button {} label: { linkLabel("공유", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PaperCapsuleStyle(prominent: false))
            }
            Button {
                showsLink = true
            } label: {
                linkLabel("QR", systemImage: "qrcode")
            }
            .buttonStyle(PaperCapsuleStyle(prominent: false))
            .accessibilityIdentifier("roomInvite.qr")
            Spacer(minLength: 0)
        }
        .disabled(invite == nil)
    }

    private func linkLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .typeScale(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
    }

    private var pickedStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(picked) { person in
                    Button {
                        toggle(person)
                    } label: {
                        VStack(spacing: 5) {
                            AvatarView(author: person.author, size: 44)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Palette.secondary)
                                        .offset(x: 4, y: -2)
                                }
                            Text(person.name)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .frame(maxWidth: 56)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(person.name) 빼기"))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func rows(_ people: [Candidate], empty: LocalizedStringKey?) -> some View {
        if people.isEmpty {
            if let empty {
                FeedPlaceholder(title: empty).padding(.top, 20)
            } else {
                KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 120)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    row(person)
                        .modifier(QuietAppear(index: index))
                    if index < people.count - 1 { Hairline() }
                }
            }
        }
    }

    private func row(_ person: Candidate) -> some View {
        let member = memberIds.contains(person.id)
        let waiting = invited.contains(person.id)
        let chosen = picked.contains { $0.id == person.id }
        return Button {
            toggle(person)
        } label: {
            HStack(spacing: 11) {
                AvatarView(author: person.author, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if person.name != person.username {
                        Text(verbatim: "@\(person.username)")
                            .typeScale(.lede)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if member || waiting {
                    Text(member ? "멤버" : "초대함")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                } else {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(chosen ? Palette.accent : Palette.faint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(member || waiting)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("roomInvite.person.\(person.username)")
    }

    private func toggle(_ person: Candidate) {
        if let at = picked.firstIndex(where: { $0.id == person.id }) {
            picked.remove(at: at)
        } else if picked.count < 20 {
            picked.append(person)
        }
    }

    private func loadList(_ source: Source) async {
        guard lists[source] == nil, let me = AuthStore.shared.me?.username else { return }
        let page = source == .following
            ? try? await FollowListsAPI.following(username: me, size: 50)
            : try? await FollowListsAPI.followers(username: me, size: 50)
        lists[source] = (page?.items ?? []).map {
            Candidate(id: $0.id, username: $0.username, displayName: nil, avatarUrl: $0.avatarUrl)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--room-pick"), picked.isEmpty {
            picked = Array((lists[source] ?? []).filter { !memberIds.contains($0.id) && !invited.contains($0.id) }.prefix(3))
        }
        #endif
    }

    private func search() async {
        guard PeopleAPI.isSearchable(query) else {
            matches = []
            searching = false
            return
        }
        searching = true
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }
        let page = try? await PeopleAPI.search(query)
        guard !Task.isCancelled else { return }
        matches = (page?.items ?? []).compactMap { match in
            match.userId.map {
                Candidate(id: $0, username: match.username, displayName: match.displayName, avatarUrl: match.avatarUrl)
            }
        }
        searching = false
    }

    private func loadInvited() async {
        if let waiting = try? await RoomAPI.invitees(roomId) {
            invited = Set(waiting.map(\.id))
            picked.removeAll { invited.contains($0.id) }
        }
    }

    private func loadLink() async {
        if let live = try? await RoomAPI.invites(roomId).first(where: { !$0.disabled }) {
            invite = live
        } else {
            invite = try? await RoomAPI.invite(roomId)
        }
        #if DEBUG
        if Config.launchValue(after: "--room-sheet") == "invite-qr" { showsLink = true }
        #endif
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let ids = picked.map(\.id)
        do {
            let waiting = try await RoomAPI.invite(roomId, people: ids)
            let reached = ids.filter { id in waiting.contains { $0.id == id } }.count
            ToastCenter.shared.show(
                reached == 0
                    ? String(localized: "초대할 수 없는 사람이에요")
                    : String(localized: "\(reached)명에게 초대를 보냈어요"))
            dismiss()
        } catch {
            failed = error.localizedDescription
        }
    }
}

struct RoomLinkSheet: View {
    let roomId: Int64
    let roomName: String
    let onChange: (RoomInvite) -> Void

    @State private var invite: RoomInvite
    @State private var limit = 0
    @State private var expiry = 0
    @State private var approval = false
    @State private var making = false
    @State private var copied = 0
    @Environment(\.dismiss) private var dismiss

    private static let limits = [0, 5, 10, 20, 50]
    private static let expiries: [(days: Int, label: LocalizedStringKey)] = [(0, "안 함"), (1, "1일"), (7, "7일")]

    init(roomId: Int64, roomName: String, invite: RoomInvite, onChange: @escaping (RoomInvite) -> Void) {
        self.roomId = roomId
        self.roomName = roomName
        self.onChange = onChange
        _invite = State(initialValue: invite)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let url = invite.shareURL {
                        VStack(spacing: 14) {
                            QRCodeImage(text: url.absoluteString)
                                .frame(width: 200, height: 200)
                                .accessibilityLabel(Text("초대 QR 코드"))
                            Text(url.absoluteString)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                            Button {
                                UIPasteboard.general.url = url
                                copied += 1
                                ToastCenter.shared.show(String(localized: "초대 링크를 복사했어요"))
                            } label: {
                                Label("링크 복사", systemImage: "link")
                            }
                            .buttonStyle(.glass)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } footer: {
                    Text("코드 \(invite.code) · \(usage)")
                }
                Section("새 링크") {
                    Picker("사용 횟수", selection: $limit) {
                        ForEach(Self.limits, id: \.self) { value in
                            Text(value == 0 ? String(localized: "제한 없음") : String(localized: "\(value)번"))
                                .tag(value)
                        }
                    }
                    Picker("만료", selection: $expiry) {
                        ForEach(Self.expiries, id: \.days) { option in
                            Text(option.label).tag(option.days)
                        }
                    }
                    Toggle("들어오기 전에 승인", isOn: $approval)
                    Button("이 설정으로 새 링크 만들기") { Task { await make() } }
                        .disabled(making)
                }
            }
            .navigationTitle("초대 링크")
            .navigationSubtitle(roomName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
            .sensoryFeedback(.success, trigger: copied)
        }
        .presentationDetents([.large])
    }

    private var usage: String {
        if let max = invite.maxUses { return String(localized: "\(invite.uses)/\(max)번 사용") }
        return String(localized: "\(invite.uses)번 사용")
    }

    private func make() async {
        making = true
        defer { making = false }
        if let next = try? await RoomAPI.invite(
            roomId,
            maxUses: limit == 0 ? nil : limit,
            expiresIn: expiry == 0 ? nil : Int64(expiry) * 86_400,
            approval: approval) {
            invite = next
            onChange(next)
        }
    }
}

struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }

    private static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
