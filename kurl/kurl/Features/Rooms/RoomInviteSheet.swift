import CoreImage.CIFilterBuiltins
import SwiftUI

struct RoomInviteSheet: View {
    let roomId: Int64
    let roomName: String
    var memberIds: Set<Int64> = []
    var preselected: [RoomPerson] = []

    @State private var query = ""
    @State private var picked: [RoomCandidate] = []
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
                RoomPeoplePicker(picked: $picked, query: query, memberIds: memberIds, invited: invited)
            }
            .animation(reduceMotion ? nil : Motion.move, value: picked)
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
                    .buttonStyle(.glassProminent)
                    .tint(GlassTokens.prominentTint)
                    .disabled(picked.isEmpty || sending)
                    .accessibilityIdentifier("roomInvite.send")
                }
            }
            .task { await loadInvited() }
            .task { await loadLink() }
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
                    .map(RoomCandidate.init)
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
            ReadingColumn(spacing: 0, background: Palette.readingBg) {
                if let url = invite.shareURL {
                    VStack(spacing: 14) {
                        QRCodeImage(text: url.absoluteString)
                            .frame(width: 196, height: 196)
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 1)
                            }
                            .accessibilityLabel(Text("초대 QR 코드"))
                        Text(url.absoluteString)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Text("코드 \(invite.code) · \(usage)")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.faint)
                        HStack(spacing: 8) {
                            Button {
                                UIPasteboard.general.url = url
                                copied += 1
                                ToastCenter.shared.show(String(localized: "초대 링크를 복사했어요"))
                            } label: {
                                capsuleLabel("링크 복사", systemImage: "link")
                            }
                            .buttonStyle(PaperCapsuleStyle(prominent: false))
                            ShareLink(item: url, subject: Text(roomName)) {
                                capsuleLabel("공유", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PaperCapsuleStyle(prominent: false))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
                RailHeading("새 링크")
                    .padding(.top, 32)
                    .padding(.bottom, 4)
                choiceRow("사용 횟수") {
                    Picker("사용 횟수", selection: $limit) {
                        ForEach(Self.limits, id: \.self) { value in
                            Text(value == 0 ? String(localized: "제한 없음") : String(localized: "\(value)번"))
                                .tag(value)
                        }
                    }
                }
                Hairline()
                choiceRow("만료") {
                    Picker("만료", selection: $expiry) {
                        ForEach(Self.expiries, id: \.days) { option in
                            Text(option.label).tag(option.days)
                        }
                    }
                }
                Hairline()
                Toggle(isOn: $approval) {
                    Text("들어오기 전에 승인")
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                }
                .tint(GlassTokens.prominentTint)
                .padding(.vertical, 9)
                Button {
                    Task { await make() }
                } label: {
                    Text("이 설정으로 새 링크 만들기")
                        .typeScale(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .contentShape(Capsule())
                }
                .buttonStyle(PaperCapsuleStyle(prominent: false))
                .disabled(making)
                .padding(.top, 16)
                .padding(.bottom, 40)
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

    private func capsuleLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .typeScale(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
    }

    private func choiceRow(_ title: LocalizedStringKey, @ViewBuilder picker: () -> some View) -> some View {
        HStack {
            Text(title)
                .typeScale(.body)
                .foregroundStyle(Palette.ink)
            Spacer()
            picker()
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Palette.secondary)
        }
        .padding(.vertical, 6)
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
