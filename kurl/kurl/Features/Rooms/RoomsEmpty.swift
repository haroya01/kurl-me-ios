import SwiftUI

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

struct EmptyRooms: View {
    let create: () -> Void
    let join: () -> Void

    @State private var feed: [PreviewPost] = []
    @State private var joined: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Friend {
        let username: String
        let name: String
    }

    private struct PreviewPost: Identifiable, Equatable {
        let id: Int
        let friend: Int
        let body: LocalizedStringKey
        let likes: Int

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    private static let friends = [
        Friend(username: "seoyeon", name: "서연"),
        Friend(username: "junho", name: "준호"),
        Friend(username: "minji", name: "민지"),
    ]

    private static let script: [(friend: Int, body: LocalizedStringKey, likes: Int)] = [
        (0, "퇴근길에 한강 들렀다. 바람이 벌써 가을이다", 2),
        (1, "오늘 처음으로 5km 안 쉬고 뛰었다", 3),
        (2, "새로 산 필름카메라 첫 롤 맡겼다. 결과 두근두근", 1),
        (0, "공방에서 만든 컵 드디어 나왔다. 손잡이 삐뚤", 2),
        (1, "비 와서 오늘은 실내 자전거", 1),
        (2, "필름 찾았다. 반은 흔들렸고 반은 마음에 든다", 3),
    ]

    private static let visible = 3

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("친구 몇 명끼리만 보는 곳")
                    .typeScale(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                Text("채팅처럼 답을 기다리지 않아도 돼요. 각자 지금 하는 걸 올려 두면 볼 때 봐요.")
                    .typeScale(.body)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: -8) {
                    if let me = AuthStore.shared.me {
                        AvatarView(
                            author: Author(id: me.id ?? 0, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl),
                            size: 44)
                    }
                    ForEach(Self.friends.indices, id: \.self) { index in
                        Circle()
                            .strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .background(Circle().fill(Palette.readingBg))
                            .frame(width: 44, height: 44)
                            .overlay {
                                AvatarView(author: Self.author(index), size: 44)
                                    .opacity(joined.contains(index) ? 1 : 0)
                                    .scaleEffect(joined.contains(index) ? 1 : 0.6)
                            }
                    }
                }
                .accessibilityHidden(true)
                Text("이름 없는 방")
                    .typeScale(.featured)
                    .foregroundStyle(Palette.faint)
                    .padding(.top, 18)
                Group {
                    if joined.isEmpty {
                        Text("나 혼자 있어요. 링크를 받은 친구만 들어와요.")
                    } else {
                        Text("친구가 들어오면 이렇게 쌓여요 · 예시")
                    }
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .contentTransition(.opacity)
                .padding(.top, 4)
                preview
                    .padding(.top, 14)
                Hairline().padding(.bottom, 16)
                HStack(spacing: 10) {
                    Text(verbatim: "kurl.me/r/······")
                        .typeScale(.body)
                        .monospaced()
                        .foregroundStyle(Palette.faint)
                    Spacer(minLength: 8)
                    Button(action: create) {
                        Text("링크 만들기")
                            .typeScale(.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(PaperCapsuleStyle(prominent: true))
                    .accessibilityIdentifier("rooms.empty.create")
                }
            }
            .padding(20)
            .background(Palette.cardBg, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            Button("받은 링크로 들어가기", action: join)
                .buttonStyle(.plain)
                .typeScale(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.secondary)
                .padding(.vertical, 14)
                .accessibilityIdentifier("rooms.empty.join")
        }
        .padding(.top, 28)
        .task { await play() }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            ForEach(feed) { post in
                row(post)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 216, alignment: .top)
        .clipped()
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(_ post: PreviewPost) -> some View {
        let friend = Self.friends[post.friend]
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(author: Self.author(post.friend), size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(verbatim: friend.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: "@\(friend.username) · ")
                            .foregroundStyle(Palette.secondary)
                            + Text("방금")
                            .foregroundStyle(Palette.secondary)
                    }
                    .lineLimit(1)
                    Text(post.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 18) {
                        HStack(spacing: 4) {
                            NoteGlyphView(glyph: .heart, size: 15)
                            Text(verbatim: "\(post.likes)").monospacedDigit()
                        }
                        NoteGlyphView(glyph: .reply, size: 15)
                    }
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
            .typeScale(.note)
            .padding(.vertical, 9)
            Hairline()
        }
    }

    private static func author(_ index: Int) -> Author {
        let friend = friends[index]
        return Author(id: Int64(-1 - index), username: friend.username, bio: nil, avatarUrl: nil, displayName: friend.name)
    }

    private func post(at step: Int) -> PreviewPost {
        let line = Self.script[step % Self.script.count]
        return PreviewPost(id: step, friend: line.friend, body: line.body, likes: line.likes)
    }

    private func play() async {
        if reduceMotion {
            feed = (0..<Self.visible).map { post(at: Self.visible - 1 - $0) }
            joined = Set(Self.friends.indices)
            return
        }
        var step = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(step == 0 ? 900 : 2_200))
            let next = post(at: step)
            withAnimation(.smooth(duration: 0.5)) {
                feed.insert(next, at: 0)
                if feed.count > Self.visible { feed.removeLast() }
                joined.insert(next.friend)
            }
            step += 1
        }
    }
}

