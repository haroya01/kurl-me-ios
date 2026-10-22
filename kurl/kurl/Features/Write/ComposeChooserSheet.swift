import SwiftUI

enum ComposeChoice: Equatable {
    case note(NoteRoom?)
    case newPost(NoteRoom?)
    case draft(MyPost)
}

/// 내 글 목록의 마지막 응답 — 앱이 뜬 뒤 미리 받아 둔(또는 스튜디오가 받은) 초안으로 글쓰기 고르기가 곧바로 그려지게 한다.
/// 로그아웃하면 AuthStore 가 비운다(다른 계정의 초안이 보이지 않게).
@MainActor
enum MyPostsCache {
    static var posts: [MyPost]?

    static func prefetch() async {
        guard posts == nil, AuthStore.shared.isSignedIn else { return }
        let account = AuthStore.shared.me?.id
        guard let fresh = try? await WriteAPI.myPosts(), posts == nil, AuthStore.shared.isSignedIn,
              account == nil || AuthStore.shared.me?.id == account
        else { return }
        posts = fresh
    }
}

/// 탭바 가운데 '글쓰기' — 어디에(모두에게·방) 무엇을(노트·긴 글) 쓸지 한 번에 고르고, 다듬던 초안을 이어 쓴다.
struct ComposeChooserSheet: View {
    let onChoose: (ComposeChoice) -> Void

    private enum Page: Hashable {
        case allDrafts
    }

    private static var lastContentHeight: CGFloat = 320
    private static var lastRooms: [RoomListItem] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var posts = MyPostsCache.posts ?? []
    @State private var rooms = ComposeChooserSheet.lastRooms
    @State private var room: NoteRoom?
    @State private var contentHeight = ComposeChooserSheet.lastContentHeight
    @State private var path: [Page] = []
    @State private var picks = 0

    private var drafts: [MyPost] {
        posts.filter(\.isDraft).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !rooms.isEmpty {
                        RailHeading("어디에")
                            .padding(.bottom, 10)
                        destinations
                            .padding(.horizontal, -Metrics.gutter)
                            .padding(.bottom, 22)
                    }
                    RailHeading("무엇을")
                        .padding(.bottom, 10)
                    HStack(spacing: 10) {
                        kindCard("노트", systemImage: "text.bubble") { onChoose(.note(room)) }
                            .accessibilityIdentifier("compose.chooser.note")
                        kindCard("긴 글", systemImage: "doc.richtext") { onChoose(.newPost(room)) }
                            .accessibilityIdentifier("compose.chooser.post")
                    }
                    if !drafts.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            RailHeading("이어 쓰기")
                            Spacer()
                            if drafts.count > 3 {
                                Button("모두 보기") { path.append(.allDrafts) }
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                                    .accessibilityIdentifier("compose.chooser.allDrafts")
                            }
                        }
                        .padding(.top, 26)
                        .padding(.bottom, 4)
                        ForEach(Array(drafts.prefix(3).enumerated()), id: \.element.id) { index, draft in
                            if index > 0 { Hairline() }
                            draftRow(draft)
                                .accessibilityIdentifier("compose.chooser.draft.\(draft.id)")
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 22)
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    guard height > 0 else { return }
                    Self.lastContentHeight = height + 24
                    contentHeight = height + 24
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.sheetBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { _ in allDrafts }
        }
        .tint(Palette.ink)
        .presentationDetents(path.isEmpty ? [.height(contentHeight), .large] : [.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: picks)
        .task { await refresh() }
        .task { await loadRooms() }
    }

    private var destinations: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                destinationChip(nil, title: String(localized: "모두에게"), systemImage: "globe")
                ForEach(rooms) { item in
                    destinationChip(NoteRoom(id: item.id, name: item.name), title: item.name, systemImage: "person.3")
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
    }

    private func destinationChip(_ target: NoteRoom?, title: String, systemImage: String) -> some View {
        let selected = room?.id == target?.id
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { room = target }
            picks += 1
        } label: {
            Label(title, systemImage: systemImage)
                .typeScale(.meta)
                .fontWeight(selected ? .semibold : .medium)
                .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    if selected {
                        Capsule().fill(Palette.hairlineStrong)
                    } else {
                        Capsule().strokeBorder(Palette.hairlineStrong, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("compose.chooser.to.\(target.map { String($0.id) } ?? "everyone")")
    }

    private func kindCard(
        _ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Palette.ink)
                Text(title)
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .buttonStyle(ChooserCardStyle())
    }

    private var allDrafts: some View {
        List(drafts) { draft in
            draftRow(draft)
                .accessibilityIdentifier("compose.chooser.allDrafts.\(draft.id)")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.sheetBg)
        .navigationTitle(Text(LocalizedStringResource("heading.drafts", defaultValue: "임시저장")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func draftRow(_ draft: MyPost) -> some View {
        Button { onChoose(.draft(draft)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if draft.title.isEmpty {
                        Text("제목 없음")
                    } else {
                        Text(verbatim: draft.title)
                    }
                }
                .typeScale(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                if let date = draft.updatedAt {
                    Text(date.relativeShort)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        guard let fresh = try? await WriteAPI.myPosts() else { return }
        MyPostsCache.posts = fresh
        guard fresh != posts else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { posts = fresh }
    }

    private func loadRooms() async {
        guard AuthStore.shared.isSignedIn, let fresh = try? await RoomAPI.mine() else { return }
        Self.lastRooms = fresh
        if fresh != rooms {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { rooms = fresh }
        }
        #if DEBUG
        if let id = Config.launchValue(after: "--chooser-room").flatMap(Int64.init),
           let item = fresh.first(where: { $0.id == id }) {
            room = NoteRoom(id: item.id, name: item.name)
        }
        #endif
    }
}

private struct ChooserCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}
