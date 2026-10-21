import SwiftUI

struct EmptyRoomsLinkFirst: View {
    let create: () -> Void
    let join: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("친구끼리만 보는 작은 블로그")
                .typeScale(.featured)
                .foregroundStyle(Palette.ink)
            Text("대화처럼 답을 기다리지 않아도 돼요. 지금 하는 걸 올려 두면 친구들이 볼 때 봐요.")
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 14) {
                step(1, "방 이름 정하기")
                step(2, "링크로 친구 부르기")
                step(3, "각자 지금 하는 걸 올리기")
            }
            .padding(.top, 24)
            Button(action: create) {
                Label("방 만들고 링크로 부르기", systemImage: "link")
                    .typeScale(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Capsule())
            }
            .buttonStyle(PaperCapsuleStyle(prominent: true))
            .padding(.top, 28)
            .accessibilityIdentifier("rooms.empty.create")
            Button("받은 초대 링크로 들어가기", action: join)
                .buttonStyle(.plain)
                .typeScale(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .accessibilityIdentifier("rooms.empty.join")
        }
        .padding(.top, 36)
    }

    private func step(_ number: Int, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(number)")
                .typeScale(.meta)
                .fontWeight(.bold)
                .foregroundStyle(Palette.secondary)
                .frame(width: 26, height: 26)
                .background(Palette.chipBg, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .typeScale(.body)
                .foregroundStyle(Palette.ink)
        }
    }
}

struct QuickRoomSheet: View {
    let onDone: (RoomDetail) -> Void

    @State private var name = ""
    @State private var making = false
    @State private var failed: String?
    @State private var made: (room: RoomDetail, link: URL)?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Group {
                if let made {
                    ready(made.room, link: made.link)
                } else {
                    naming
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.readingBg)
            .navigationTitle(made == nil ? "새 방" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let made {
                        Button("방으로 가기") { onDone(made.room) }
                    } else {
                        Button("취소") { dismiss() }
                    }
                }
                if made == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await make() }
                        } label: {
                            if making { ProgressView() } else { Text("만들기") }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(GlassTokens.prominentTint)
                        .disabled(trimmed.isEmpty || trimmed.count > 50 || making)
                        .accessibilityIdentifier("quickRoom.make")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(made != nil)
    }

    private var naming: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("방 이름", text: $name)
                .typeScale(.title)
                .foregroundStyle(Palette.ink)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { Task { await make() } }
                .padding(.vertical, 12)
                .accessibilityIdentifier("quickRoom.name")
            Hairline()
            Text("만들면 바로 초대 링크를 보낼 수 있어요. 최대 50명, 방 글은 멤버만 봐요.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 10)
            if let failed {
                Text(failed)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.danger)
                    .padding(.top, 6)
            }
        }
        .onAppear { focused = true }
    }

    private func ready(_ room: RoomDetail, link: URL) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: room.name)
                .typeScale(.featured)
                .foregroundStyle(Palette.ink)
            Text("방이 생겼어요. 링크를 받은 친구는 바로 들어와요.")
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 6)
            Text(link.absoluteString)
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.top, 18)
            ShareLink(item: link, subject: Text(room.name)) {
                Label("링크 보내기", systemImage: "square.and.arrow.up")
                    .typeScale(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Capsule())
            }
            .buttonStyle(PaperCapsuleStyle(prominent: true))
            .padding(.top, 14)
            .accessibilityIdentifier("quickRoom.share")
        }
    }

    private func make() async {
        guard !trimmed.isEmpty, trimmed.count <= 50, !making else { return }
        making = true
        defer { making = false }
        let room: RoomDetail
        do {
            room = try await RoomAPI.create(name: trimmed)
        } catch {
            failed = error.localizedDescription
            return
        }
        RoomsRouter.shared.changed()
        if let link = (try? await RoomAPI.invite(room.id))?.shareURL {
            made = (room, link)
        } else {
            onDone(room)
        }
    }
}
