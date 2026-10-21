//
//  NotesView.swift
//  kurl
//

import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class NotesViewModel {
    private(set) var loaded: [Note] = []
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var isLoadingMore = false

    var items: [Note] {
        guard source.filterContext != nil else { return loaded }
        return loaded.filter(isVisible)
    }

    private func isVisible(_ note: Note) -> Bool {
        guard let context = source.filterContext else { return true }
        return NoteFilterStore.shared.verdict(for: note, in: context) != .hide
    }

    private nonisolated static let chaseCap = 5

    /// 받은 페이지의 노트가 필터로 전부 숨겨지면 다음 페이지를 이어 받는다(상한 `chaseCap`).
    static func collectVisible(
        from startPage: Int,
        seen: Set<Int64>,
        cap: Int = chaseCap,
        isVisible: (Note) -> Bool,
        fetch: (Int) async throws -> NoteFeed
    ) async throws -> (notes: [Note], page: Int, hasNext: Bool) {
        var seen = seen
        var notes: [Note] = []
        var page = startPage
        var hops = 0
        while true {
            let feed = try await fetch(page)
            let fresh = feed.items.filter { seen.insert($0.id).inserted }
            notes += fresh
            hops += 1
            if fresh.contains(where: isVisible) || !feed.hasNext || hops >= cap {
                return (notes, page, feed.hasNext)
            }
            page += 1
        }
    }

    var filterContext: NoteFilterContext? { source.filterContext }

    private var page = 0
    private var hasNext = true
    private var epoch = 0
    private var source: Source

    enum Source: Equatable {
        case everyone
        case federated
        case following
        case trending
        case bookmarks
        case direct
        case list(Int64)
        case room(Int64)
        case rooms
        case author(String)
        case reposts(String)
        case quotes(Int64)
        case tag(String)
        case link(String)
        case search(String)
        case remoteAccount(Int64)

        var filterContext: NoteFilterContext? {
            switch self {
            case .everyone, .federated, .trending, .tag, .link, .quotes, .search: .public
            case .following, .list: .home
            case .author, .reposts, .remoteAccount: .account
            case .bookmarks, .direct, .room, .rooms: nil
            }
        }

        init(_ feed: NoteFeedKind) {
            switch feed {
            case .everyone: self = .everyone
            case .federated: self = .federated
            case .following: self = .following
            case .trending: self = .trending
            case .bookmarks: self = .bookmarks
            case .direct: self = .direct
            case .list: self = .list(0)
            }
        }
    }

    init(author: String? = nil) {
        source = author.map(Source.author) ?? .everyone
    }

    init(feed: NoteFeedKind) {
        source = Source(feed)
    }

    init(list id: Int64) {
        source = .list(id)
    }

    init(room id: Int64) {
        source = .room(id)
    }

    init(source: Source) {
        self.source = source
    }

    init(repostsBy username: String) {
        source = .reposts(username)
    }

    init(quotesOf id: Int64) {
        source = .quotes(id)
    }

    init(tag: String) {
        source = .tag(tag)
    }

    init(link url: String) {
        source = .link(url)
    }

    init(search query: String) {
        source = .search(query)
    }

    init(remoteAccount id: Int64) {
        source = .remoteAccount(id)
    }

    private func load(_ page: Int) async throws -> NoteFeed {
        switch source {
        case .everyone: try await NoteAPI.everyone(page: page)
        case .federated:
            if AuthStore.shared.isSignedIn {
                try await NoteAPI.federated(page: page)
            } else {
                NoteFeed(items: [], page: 0, hasNext: false)
            }
        case .following:
            if AuthStore.shared.isSignedIn {
                try await NoteAPI.following(page: page)
            } else {
                NoteFeed(items: [], page: 0, hasNext: false)
            }
        case .trending: try await NoteAPI.trending(page: page)
        case .bookmarks:
            if AuthStore.shared.isSignedIn {
                try await NoteAPI.bookmarks(page: page)
            } else {
                NoteFeed(items: [], page: 0, hasNext: false)
            }
        case .direct:
            if AuthStore.shared.isSignedIn {
                try await NoteAPI.direct(page: page)
            } else {
                NoteFeed(items: [], page: 0, hasNext: false)
            }
        case let .list(id):
            if AuthStore.shared.isSignedIn, id > 0 {
                try await NoteAPI.listNotes(id: id, page: page)
            } else {
                NoteFeed(items: [], page: 0, hasNext: false)
            }
        case let .room(id): try await RoomAPI.notes(room: id, page: page)
        case .rooms: try await RoomAPI.feed(page: page)
        case let .quotes(id): try await NoteAPI.quotes(of: id, page: page)
        case let .tag(name): try await NoteAPI.tagged(name, page: page)
        case let .link(url): try await NoteAPI.linked(url, page: page)
        case let .search(query): try await NoteAPI.search(query, page: page)
        case let .author(username): try await NoteAPI.byAuthor(username, page: page)
        case let .reposts(username): try await NoteAPI.reposts(username, page: page)
        case let .remoteAccount(id): try await NoteAPI.remoteAccountNotes(id: id, page: page)
        }
    }

    func show(_ next: Source) async {
        guard next != source else { return }
        source = next
        epoch += 1
        loaded = []
        page = 0
        hasNext = true
        phase = .loading
        await reload()
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        if loaded.isEmpty { phase = .loading }
        do {
            let head = try await Self.collectVisible(from: 0, seen: [], isVisible: isVisible) {
                try await self.load($0)
            }
            guard myEpoch == epoch else { return }
            page = head.page
            loaded = head.notes
            hasNext = head.hasNext
            phase = .loaded(true)
        } catch {
            guard myEpoch == epoch else { return }
            if loaded.isEmpty {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            } else {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
        }
    }

    func loadMoreIfNeeded(current note: Note) async {
        guard hasNext, !isLoadingMore, items.last?.id == note.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let myEpoch = epoch
        if let next = try? await Self.collectVisible(
            from: page + 1, seen: Set(loaded.map(\.id)), isVisible: isVisible, fetch: { try await self.load($0) }
        ) {
            guard myEpoch == epoch else { return }
            page = next.page
            hasNext = next.hasNext
            loaded.append(contentsOf: next.notes)
        }
    }

    func inserted(_ note: Note) {
        withAnimation(.snappy(duration: 0.3)) {
            phase = .loaded(true)
            loaded.insert(note, at: 0)
        }
    }

    func replaced(_ note: Note) {
        guard let index = loaded.firstIndex(where: { $0.id == note.id }) else { return }
        var next = note
        next.repostedBy = next.repostedBy ?? loaded[index].repostedBy
        loaded[index] = next
    }

    func removed(_ id: Int64) {
        _ = withAnimation(.snappy(duration: 0.25)) { loaded.removeAll { $0.id == id } }
    }
}

struct NoteRowDetached {
    let context: Text?
    let open: () -> Void
    let openAuthor: () -> Void
    let reply: () -> Void
    let menu: AnyView
    let actions: AnyView
}

/// 노트 한 행 — 스레드 행 문법(헤어라인 구분). 고치기·지우기는 더보기 메뉴나 길게 눌러서.
struct NoteRowView: View {
    let note: Note
    let onChange: (Note) -> Void
    let onDelete: (Int64) -> Void
    var onQuoted: ((Note) -> Void)? = nil
    var repostedBy: String? = nil
    /// 프로필 노트 탭에서만 "고정됨" 줄을 보인다 — 다른 피드에선 고정이 의미 없다(마스토돈과 같다).
    var showsPin = false
    var replyHeader: ReplyHeader? = nil
    /// 원글 → 답글을 잇는 스레드 선 — 아바타 아래에서 다음 행 아바타 위까지.
    var threadLineBelow = false
    /// 상세의 본 노트 — 머리 줄 아래로 본문을 전체 폭에 한 단계 크게(스레드·X 문법).
    var focused = false
    /// 이어 쓴 노트의 몇 번째 편인지("1/3") — 스레드처럼 머리 줄 끝에.
    var position: String? = nil
    var onReplied: ((Note) -> Void)? = nil
    var detached: NoteRowDetached? = nil

    @State private var replying = false
    @State private var replyPosts = 0
    @State private var liked: Bool
    @State private var likeCount: Int64?
    @State private var likeTaps = 0
    @State private var reposted: Bool
    @State private var addingToSeries = false
    @State private var repostCount: Int64?
    @State private var repostTaps = 0
    @State private var bookmarked: Bool
    @State private var bookmarkTaps = 0
    @State private var conversationMuted: Bool
    @State private var reporting = false
    @State private var quoting = false
    @State private var writingPost = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var connecting = false
    @State private var showLoginSheet = false
    @State private var loginMessage: LocalizedStringKey = "좋아요를 누르려면 로그인하세요"
    @State private var revealed = false
    @State private var mediaRevealed = false
    @State private var showingHistory = false
    @State private var filterRevealed = false
    @State private var translations = ContentTranslations.shared
    @State private var translationSource: Locale.Language?
    @State private var translationRequest: TranslationRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.noteFilterContext) private var filterContext
    @Environment(\.openNoteRoute) private var openNoteRoute
    @Environment(\.insideRoom) private var insideRoom
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .callout) private var nameCapCenter: CGFloat = 9
    @ScaledMetric(relativeTo: .callout) private var nameCapHalf: CGFloat = 5.3

    private var unit: CGFloat { min(scale, 1.8) }

    init(note: Note, onChange: @escaping (Note) -> Void,
         onDelete: @escaping (Int64) -> Void,
         onQuoted: ((Note) -> Void)? = nil, repostedBy: String? = nil,
         showsPin: Bool = false, replyHeader: ReplyHeader? = nil,
         threadLineBelow: Bool = false, focused: Bool = false, position: String? = nil,
         onReplied: ((Note) -> Void)? = nil, detached: NoteRowDetached? = nil) {
        self.note = note
        self.onChange = onChange
        self.onDelete = onDelete
        self.onQuoted = onQuoted
        self.repostedBy = repostedBy
        self.showsPin = showsPin
        self.replyHeader = replyHeader
        self.threadLineBelow = threadLineBelow
        self.focused = focused
        self.position = position
        self.onReplied = onReplied
        self.detached = detached
        _liked = State(initialValue: note.likedByMe == true)
        _likeCount = State(initialValue: note.likeCount)
        _reposted = State(initialValue: note.repostedByMe == true)
        _repostCount = State(initialValue: note.repostCount)
        _bookmarked = State(initialValue: note.bookmarkedByMe == true)
        _conversationMuted = State(initialValue: note.conversationMuted == true)
    }

    private var isMine: Bool { AuthStore.shared.me?.id == note.author.id }
    /// 시리즈에 넣을 수 있는 노트 — 내 노트이고 시리즈 독자가 읽을 수 있는 범위(공개·조용한 공개).
    private var seriesAddable: Bool { isMine && note.noteVisibility.shareable }

    private var filteredPhrases: [String]? {
        guard !filterRevealed, let filterContext,
              case let .warn(phrases) = NoteFilterStore.shared.verdict(for: note, in: filterContext)
        else { return nil }
        return phrases
    }

    var body: some View {
        if let filteredPhrases {
            filteredBar(filteredPhrases)
        } else {
            content
        }
    }

    private func filteredBar(_ phrases: [String]) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { filterRevealed = true }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("필터됨: \(phrases.joined(separator: ", "))")
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Text("보기")
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .typeScale(.meta)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note.filtered.reveal.\(note.id)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note.filtered.\(note.id)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let context = detached?.context {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 36 * unit, height: 1)
                    context
                        .typeScale(.meta)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                .foregroundStyle(Palette.secondary)
                .allowsHitTesting(false)
            } else if let repostedBy {
                HStack(spacing: 12) {
                    NoteGlyphView(glyph: .repost, size: 14 * unit)
                        .frame(width: 36 * unit, alignment: .trailing)
                    Text("\(repostedBy)님이 리포스트함")
                        .typeScale(.meta)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.secondary)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            } else if let room = note.room, insideRoom != room.id {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 36 * unit, height: 1)
                    Button {
                        RoomsRouter.shared.open(room.id)
                    } label: {
                        Text("\(room.name) 방에서")
                            .typeScale(.meta)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.room.\(note.id)")
                }
                .foregroundStyle(Palette.secondary)
            } else if let replyHeader {
                ReplyHeaderLine(header: replyHeader)
            } else if showsPin, note.pinned == true {
                HStack(spacing: 12) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12 * unit, weight: .semibold))
                        .frame(width: 36 * unit, alignment: .trailing)
                    Text("고정됨")
                        .typeScale(.meta)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Palette.secondary)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("note.pinned.\(note.id)")
            }
            if focused { focusedRow } else { row }
        }
        .padding(.vertical, focused ? 14 : 12)
        .overlay(alignment: .topLeading) {
            if threadLineBelow {
                Capsule()
                    .fill(Palette.hairlineStrong)
                    .frame(width: 2)
                    .padding(.top, (focused ? 14 : 12) + 36 * unit + 6)
                    .padding(.bottom, -8)
                    .padding(.leading, 18 * unit - 1)
                    .accessibilityHidden(true)
            }
        }
        .background {
            if let detached {
                Button(action: detached.open) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            } else if !focused {
                NavigationLink(value: Route.note(id: note.id)) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !note.body.isEmpty {
                Button {
                    UIPasteboard.general.string = note.body
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
            }
            if isMine {
                if note.inReplyToId == nil {
                    Button {
                        Task { await togglePin() }
                    } label: {
                        Label(
                            note.pinned == true ? LocalizedStringKey("고정 해제") : LocalizedStringKey("프로필에 고정"),
                            systemImage: note.pinned == true ? "pin.slash" : "pin")
                    }
                }
                if seriesAddable {
                    Button { addingToSeries = true } label: {
                        Label("시리즈에 넣기", systemImage: "books.vertical")
                    }
                }
                Button { editing = true } label: { Label("고치기", systemImage: "pencil") }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("노트 삭제", systemImage: "trash")
                }
            }
            if AuthStore.shared.isSignedIn, detached == nil {
                Button { connecting = true } label: {
                    Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
                }
            }
        }
        .sheet(isPresented: $editing) {
            NoteComposeSheet(mode: .edit(note)) { onChange($0) }
        }
        .sheet(isPresented: $replying) {
            NoteComposeSheet(mode: .reply(note)) { replied($0) }
        }
        .sensoryFeedback(.success, trigger: replyPosts)
        .sheet(isPresented: $quoting) {
            NoteComposeSheet(mode: .quote(QuotedNote(note))) { created in
                ToastCenter.shared.show(String(localized: "인용 노트를 올렸어요"))
                onQuoted?(created)
            }
        }
        .sheet(isPresented: $connecting) {
            ConnectSheet(targetKind: "노트", targetTitle: note.body, blockType: .note, refId: note.id)
        }
        .sheet(isPresented: $addingToSeries) {
            AddNoteToSeriesSheet(noteId: note.id)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $writingPost) {
            if let shareURL { PostComposerCover(initialMarkdown: "\(shareURL.absoluteString)\n\n") }
        }
        .alert("이 노트를 지울까요?", isPresented: $confirmDelete) {
            Button("지우기", role: .destructive) { Task { await delete() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("다른 서버로 퍼진 사본에도 지우라는 요청을 보내요.")
        }
        .loginPrompt(isPresented: $showLoginSheet, message: loginMessage)
        .task(id: "\(note.id)|\(note.body.hashValue)|\(note.language ?? "")") { await probeTranslation() }
        .translationRunner($translationRequest)
        .onChange(of: note) { _, next in
            liked = next.likedByMe == true
            likeCount = next.likeCount
            reposted = next.repostedByMe == true
            repostCount = next.repostCount
            bookmarked = next.bookmarkedByMe == true
            conversationMuted = next.conversationMuted == true
        }
    }

    @ViewBuilder private var avatarLink: some View {
        if let detached {
            Button(action: detached.openAuthor) {
                ConversationAvatar(author: note.author)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(ConversationName.spoken(note.author))님 프로필"))
        } else {
            NavigationLink(value: note.author.notesRoute) {
                ConversationAvatar(author: note.author)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(ConversationName.spoken(note.author))님 프로필"))
        }
    }

    private var focusedRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink(value: note.author.notesRoute) {
                    AvatarView(author: note.author, size: 44 * unit)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                NavigationLink(value: note.author.notesRoute) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.author.shownName)
                            .typeScale(.note)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: note.author.isRemote
                            ? "@\(note.author.username)"
                            : "@\(note.author.username)@\(Self.federationHost)")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                if let position {
                    Text(verbatim: position)
                        .typeScale(.meta)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                        .accessibilityLabel(Text("이어 쓴 노트 \(position)"))
                        .accessibilityIdentifier("note.position.\(note.id)")
                }
                if !note.author.isRemote {
                    FollowButton(username: note.author.username)
                }
                moreMenu
            }
            warningLine
            if !note.body.isEmpty, folded || note.remoteCard == nil {
                ZStack(alignment: .topLeading) {
                    if folded {
                        shield(.noteFocus)
                    } else {
                        Text(NoteText.attributed(shownBody, mentions: note.mentions ?? []))
                            .typeScale(.noteFocus)
                            .foregroundStyle(Palette.ink)
                            .tint(Palette.link)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .transition(.opacity)
                    }
                }
                if !folded { translationLine }
            }
            attachments
            if let date = note.createdAt {
                HStack(spacing: 4) {
                    Text(date, format: .dateTime.hour().minute())
                    Text(verbatim: "·")
                    Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    if note.editedAt != nil {
                        Text(verbatim: "·")
                        Button("고침") { showingHistory = true }
                            .buttonStyle(.plain)
                            .underline()
                            .accessibilityHint("수정 기록 보기")
                            .accessibilityIdentifier("note.history.\(note.id)")
                    }
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .accessibilityElement(children: .contain)
                .sheet(isPresented: $showingHistory) {
                    NoteHistorySheet(noteId: note.id)
                }
            }
            VStack(spacing: 0) {
                Hairline()
                actions(spread: true)
                    .padding(.top, 10)
                if let quotes = note.quoteCount, quotes > 0 {
                    NavigationLink(value: Route.noteQuotes(id: note.id)) {
                        HStack(spacing: 4) {
                            Text("인용 \(quotes)")
                                .typeScale(.meta)
                                .fontWeight(.semibold)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12 * unit, weight: .semibold))
                        }
                        .foregroundStyle(Palette.secondary)
                        .padding(.top, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.quotes.\(note.id)")
                }
            }
        }
    }

    private static let federationHost = Config.apiBase.host() ?? "kurl.me"

    private var row: some View {
        HStack(alignment: .noteNameLine, spacing: 12) {
            avatarLink
                .alignmentGuide(.noteNameLine) { $0[.top] + nameCapCenter }

            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    header
                    warningLine
                    if !note.body.isEmpty, folded || note.remoteCard == nil {
                        ZStack(alignment: .topLeading) {
                            if folded {
                                shield(.note)
                            } else if let detached {
                                Button(action: detached.open) { feedBody }
                                    .buttonStyle(.plain)
                                    .transition(.opacity)
                            } else {
                                NavigationLink(value: Route.note(id: note.id)) { feedBody }
                                    .buttonStyle(.plain)
                                    .transition(.opacity)
                                    .accessibilityIdentifier("note.body.\(note.id)")
                            }
                        }
                    }
                }
                .conversationGrouping(label: spokenLine, identifier: "note.row.\(note.id)") {
                    if note.contentWarning != nil {
                        Button(revealed ? LocalizedStringKey("숨기기") : LocalizedStringKey("보기")) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { revealed.toggle() }
                        }
                    }
                    if let detached {
                        Button("답글 쓰기", action: detached.reply)
                    } else if !replyAccess.isClosed {
                        Button("답글 쓰기") { startReply() }
                    }
                }
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                    if let detached {
                        detached.menu
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + nameCapHalf }
                    } else {
                        moreMenu
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + nameCapHalf }
                    }
                }
                if !folded, !note.body.isEmpty, note.remoteCard == nil { translationLine }
                attachments
                if let detached {
                    detached.actions
                        .padding(.top, 6)
                } else {
                    actions(spread: false)
                        .padding(.top, 6)
                }
            }
            .alignmentGuide(.noteNameLine) { $0[.firstTextBaseline] - nameCapHalf }
        }
    }

    private var feedBody: some View {
        Text(NoteText.attributed(shownBody, mentions: note.mentions ?? []))
            .typeScale(.note)
            .foregroundStyle(Palette.ink)
            .tint(Palette.link)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// ⋯ 는 VoiceOver 묶음 밖에 얹어야 따로 닿는다 — 여기선 자리만 비운다.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let detached {
                Button(action: detached.openAuthor) {
                    ConversationName(author: note.author)
                        .typeScale(.note)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: note.author.notesRoute) {
                    ConversationName(author: note.author)
                        .typeScale(.note)
                }
                .buttonStyle(.plain)
            }
            if let date = note.createdAt {
                Text(verbatim: "·")
                    .typeScale(.note)
                    .foregroundStyle(Palette.faint)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text(date.relativeCompact)
                    .typeScale(.note)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize()
                    .allowsHitTesting(false)
            }
            if note.noteVisibility != .public, note.room == nil {
                Image(systemName: note.noteVisibility.symbol)
                    .font(.system(size: 11 * unit, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .allowsHitTesting(false)
                    .accessibilityLabel(note.room.map { Text("\($0.name) 멤버만") } ?? Text(note.noteVisibility.title))
                    .accessibilityIdentifier("note.visibility.\(note.id)")
            }
            if note.editedAt != nil {
                Text("고침")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
            if let position {
                Text(verbatim: position)
                    .typeScale(.meta)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                    .allowsHitTesting(false)
                    .accessibilityLabel(Text("이어 쓴 노트 \(position)"))
                    .accessibilityIdentifier("note.position.\(note.id)")
            }
            Color.clear
                .frame(width: 32 * unit, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var spokenLine: String {
        var parts = [ConversationName.spoken(note.author)]
        if let date = note.createdAt { parts.append(date.relativeCompact) }
        switch note.noteVisibility {
        case .public: break
        case .unlisted: parts.append(String(localized: "조용한 공개"))
        case .private: parts.append(note.room.map { String(localized: "\($0.name) 멤버만") } ?? String(localized: "팔로워만"))
        case .direct: parts.append(String(localized: "멘션한 사람만"))
        }
        if note.editedAt != nil { parts.append(String(localized: "고침")) }
        if let position { parts.append(String(localized: "이어 쓴 노트 \(position)")) }
        if let warning = note.contentWarning { parts.append(translated?.warning ?? warning) }
        if !folded, !note.body.isEmpty { parts.append(shownBody) }
        return parts.joined(separator: ", ")
    }

    private var folded: Bool { note.contentWarning != nil && !revealed }

    private var translationKey: String { NoteTranslation.key(note) }

    private var translated: (body: String, warning: String?)? {
        translations.shown(translationKey).map {
            NoteTranslation.apply($0, body: note.body, warning: note.contentWarning)
        }
    }

    private var shownBody: String { translated?.body ?? note.body }

    @ViewBuilder private var translationLine: some View {
        if let source = translationSource {
            NoteTranslationLine(
                noteId: note.id, source: source, phase: translations.phases[translationKey],
                translate: translate, showOriginal: showOriginal)
        }
    }

    private func translate() {
        guard let source = translationSource else { return }
        let key = translationKey
        if translations.showCached(key) { return }
        let request = TranslationRequest(
            key: key, source: source, target: TranslationGate.target(),
            texts: NoteTranslation.requests(body: note.body, warning: note.contentWarning))
        translations.begin(request)
        translationRequest = request
    }

    private func showOriginal() {
        translationRequest = nil
        translations.showOriginal(translationKey)
    }

    private func probeTranslation() async {
        let text = NoteTranslation.requests(NoteTranslation.parts(note.body)).joined(separator: " ")
        let declared = note.language
        let source = await Task.detached(priority: .utility) {
            TranslationGate.source(declared: declared, text: text)
        }.value
        guard !Task.isCancelled else { return }
        let available = if let source { await translations.isAvailable(from: source, to: TranslationGate.target()) } else { false }
        let next = available ? source : nil
        if translationSource != next { translationSource = next }
        if Config.autoTranslate, next != nil, translations.phases[translationKey] == nil { translate() }
    }

    @ViewBuilder private var warningLine: some View {
        if let warning = note.contentWarning {
            Text(translated?.warning ?? warning)
                .typeScale(focused ? .noteFocus : .note)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityIdentifier("note.warning.\(note.id)")
        }
    }

    private func shield(_ scale: TypeRole) -> some View {
        Button(action: reveal) {
            Text(verbatim: note.body)
                .typeScale(scale)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .blur(radius: 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityLabel(Text("가려진 내용"))
        .accessibilityAction(named: Text("보기"), reveal)
        .accessibilityIdentifier("note.reveal.\(note.id)")
    }

    private func reveal() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { revealed = true }
    }

    private var mediaConcealed: Bool {
        guard !note.media.isEmpty else { return false }
        if note.contentWarning != nil { return !revealed }
        return note.sensitive == true && !mediaRevealed
    }

    private func revealMedia() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            if note.contentWarning != nil { revealed = true } else { mediaRevealed = true }
        }
    }

    @ViewBuilder private var attachments: some View {
        if let shape = note.remoteCard {
            remoteCardAttachments(shape)
        } else {
            if !folded, let poll = note.poll {
                NotePollView(noteId: note.id, poll: poll, remote: note.remote) { updated in
                    var next = note
                    next.poll = updated
                    onChange(next)
                }
                .padding(.top, 8)
            }
            NoteImagesView(
                media: note.media, concealed: mediaConcealed, revealIdentifier: "note.sensitive.\(note.id)",
                reveal: revealMedia)
            if !folded {
                quotedAttachments
            }
        }
    }

    @ViewBuilder private func remoteCardAttachments(_ shape: RemoteNoteShape) -> some View {
        let picture = RemoteNoteCard.picture(in: note)
        if !folded {
            RemoteNoteCard(noteId: note.id, shape: shape, summary: shownBody, picture: picture, full: focused)
                .padding(.top, focused ? 0 : 6)
            if !note.body.isEmpty { translationLine }
        }
        NoteImagesView(
            media: note.media.filter { $0 != picture }, concealed: mediaConcealed,
            revealIdentifier: "note.sensitive.\(note.id)", reveal: revealMedia)
    }

    @ViewBuilder private var quotedAttachments: some View {
        if let post = note.quotedPost {
            NavigationLink(value: Route.post(username: post.authorUsername, slug: post.slug)) {
                QuotedPostCard(post: post)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        if let quoted = note.quotedNote {
            NavigationLink(value: Route.note(id: quoted.id)) {
                QuotedNoteCard(note: quoted)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityIdentifier("note.quoted.\(quoted.id)")
        }
        if let card = note.linkPreview, let url = URL(string: card.url) {
            Link(destination: url) {
                NoteLinkCardView(preview: card)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityIdentifier("note.linkCard.\(note.id)")
        }
    }

    private var shareURL: URL? {
        URL(string: "\(Config.blogBase)/@\(note.author.username)/notes/\(note.id)")
    }

    private var moreMenu: some View {
        Menu {
            if !note.body.isEmpty {
                Button {
                    UIPasteboard.general.string = note.body
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
            }
            if AuthStore.shared.isSignedIn {
                Button {
                    bookmarkTaps += 1
                    Task { await toggleBookmark() }
                } label: {
                    Label(
                        bookmarked ? LocalizedStringKey("북마크 해제") : LocalizedStringKey("북마크"),
                        systemImage: bookmarked ? "bookmark.slash" : "bookmark")
                }
                Button { connecting = true } label: {
                    Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
                }
                Button {
                    Task { await toggleConversationMute() }
                } label: {
                    Label(
                        conversationMuted ? LocalizedStringKey("대화 알림 켜기") : LocalizedStringKey("대화 알림 끄기"),
                        systemImage: conversationMuted ? "bell" : "bell.slash")
                }
                .accessibilityIdentifier("note.conversationMute.\(note.id)")
                if !isMine {
                    Button(role: .destructive) { reporting = true } label: {
                        Label("신고", systemImage: "flag")
                    }
                    .accessibilityIdentifier("note.report.\(note.id)")
                }
            }
            if isMine {
                Divider()
                if note.inReplyToId == nil {
                    Button {
                        Task { await togglePin() }
                    } label: {
                        Label(
                            note.pinned == true ? LocalizedStringKey("고정 해제") : LocalizedStringKey("프로필에 고정"),
                            systemImage: note.pinned == true ? "pin.slash" : "pin")
                    }
                }
                if seriesAddable {
                    Button { addingToSeries = true } label: {
                        Label("시리즈에 넣기", systemImage: "books.vertical")
                    }
                    .accessibilityIdentifier("note.addToSeries.\(note.id)")
                }
                Button { editing = true } label: { Label("고치기", systemImage: "pencil") }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("노트 삭제", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15 * unit, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 32 * unit, height: 22 * unit)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("노트 메뉴")
        .accessibilityIdentifier("note.menu.\(note.id)")
        .reportDialog(
            isPresented: $reporting, subjectType: "NOTE", subjectId: note.id,
            forwardDomain: note.author.isRemote ? note.author.username.split(separator: "@").last.map(String.init) : nil)
    }

    private func actions(spread: Bool) -> some View {
        HStack(spacing: spread ? 0 : 20) {
            Button {
                likeTaps += 1
                Task { await toggleLike() }
            } label: {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .heart, active: liked, size: Self.actionBox * unit)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : liked))
                    if let likeCount, likeCount > 0 {
                        Text("\(likeCount)")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(likeCount)))
                    }
                }
                .typeScale(.lede)
                .foregroundStyle(liked ? Palette.accent : Palette.ink)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
            .accessibilityLabel(Text("좋아요"))
            .accessibilityAddTraits(liked ? [.isSelected] : [])

            if spread { Spacer(minLength: 0) }
            replyButton

            if note.room == nil {
                if spread { Spacer(minLength: 0) }
                repostMenu
            }

            if spread {
                Spacer(minLength: 0)
                Button {
                    bookmarkTaps += 1
                    Task { await toggleBookmark() }
                } label: {
                    NoteGlyphView(glyph: .bookmark, active: bookmarked, size: Self.actionBox * unit)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : bookmarked))
                        .foregroundStyle(bookmarked ? Palette.accent : Palette.ink)
                        .expandTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(bookmarked ? "북마크 해제" : "북마크"))
                .accessibilityAddTraits(bookmarked ? [.isSelected] : [])
                .accessibilityIdentifier("note.bookmark.\(note.id)")
            }

            if let shareURL, note.room == nil {
                if spread { Spacer(minLength: 0) }
                shareMenu(shareURL)
            }
        }
    }

    private static let actionBox: CGFloat = 20

    /// X의 공유 메뉴처럼 — 시스템 공유, 링크 복사, 그리고 이 노트를 카드로 실은 새 블로그 글.
    private func shareMenu(_ url: URL) -> some View {
        Menu {
            ShareLink(item: url) {
                Label("공유…", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.url = url
                ToastCenter.shared.show(String(localized: "링크를 복사했어요"))
            } label: {
                Label("링크 복사", systemImage: "link")
            }
            if note.noteVisibility.shareable {
                Button {
                    if AuthStore.shared.isSignedIn { writingPost = true } else { askLogin("블로그 글로 인용하려면 로그인하세요") }
                } label: {
                    Label("블로그 글로 인용", systemImage: "square.and.pencil")
                }
            }
        } label: {
            NoteGlyphView(glyph: .share, size: Self.actionBox * unit)
                .foregroundStyle(Palette.ink)
                .expandTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("공유"))
        .accessibilityIdentifier("note.share.\(note.id)")
    }

    @ViewBuilder private var repostMenu: some View {
        if note.noteVisibility.shareable {
            shareableRepostMenu
        } else {
            NoteGlyphView(glyph: .repost, active: false, size: Self.actionBox * unit)
                .foregroundStyle(Palette.faint)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8 * unit, weight: .bold))
                        .foregroundStyle(Palette.faint)
                }
                .expandTapTarget()
                .accessibilityLabel(Text("리포스트할 수 없는 노트"))
                .accessibilityIdentifier("note.repost.\(note.id)")
        }
    }

    private var shareableRepostMenu: some View {
        Menu {
            Button(role: reposted ? .destructive : nil) {
                repostTaps += 1
                Task { await toggleRepost() }
            } label: {
                Label(
                    reposted ? LocalizedStringKey("리포스트 취소") : LocalizedStringKey("리포스트"),
                    systemImage: "arrow.2.squarepath")
            }
            Button {
                if AuthStore.shared.isSignedIn { quoting = true } else { askLogin("인용하려면 로그인하세요") }
            } label: {
                Label("인용", systemImage: "quote.opening")
            }
        } label: {
            HStack(spacing: 4) {
                NoteGlyphView(glyph: .repost, active: reposted, size: Self.actionBox * unit)
                    .modifier(GlyphPop(trigger: reduceMotion ? false : reposted))
                if let repostCount, repostCount > 0 {
                    Text("\(repostCount)")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(repostCount)))
                }
            }
            .typeScale(.lede)
            .foregroundStyle(reposted ? Palette.accent : Palette.ink)
            .expandTapTarget()
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: repostTaps)
        .accessibilityLabel(Text("리포스트 메뉴"))
        .accessibilityAddTraits(reposted ? [.isSelected] : [])
        .accessibilityIdentifier("note.repost.\(note.id)")
    }

    private func toggleRepost() async {
        guard AuthStore.shared.isSignedIn else {
            askLogin("리포스트하려면 로그인하세요")
            return
        }
        let target = !reposted
        let previous = repostCount
        withAnimation(.snappy(duration: 0.2)) {
            reposted = target
            repostCount = max((repostCount ?? 0) + (target ? 1 : -1), 0)
        }
        do {
            let status = try await NoteAPI.setRepost(id: note.id, on: target)
            withAnimation(.snappy(duration: 0.2)) { repostCount = status.repostCount }
        } catch {
            reposted = !target
            repostCount = previous
            ToastCenter.shared.show(String(localized: "리포스트하지 못했어요"))
        }
    }

    private func togglePin() async {
        let target = note.pinned != true
        do {
            let status = try await NoteAPI.setPin(id: note.id, on: target)
            var updated = note
            updated.pinned = status.pinned
            onChange(updated)
            ToastCenter.shared.show(String(localized: status.pinned ? "프로필에 고정했어요" : "고정을 풀었어요"))
        } catch let APIError.server(_, code, _) where code == "NOTE_PIN_LIMIT" {
            ToastCenter.shared.show(String(localized: "고정은 5개까지예요. 다른 노트를 먼저 풀어 주세요"))
        } catch {
            ToastCenter.shared.show(String(localized: "고정을 바꾸지 못했어요"))
        }
    }

    private func toggleBookmark() async {
        guard AuthStore.shared.isSignedIn else {
            askLogin("북마크하려면 로그인하세요")
            return
        }
        let target = !bookmarked
        bookmarked = target
        do {
            _ = try await NoteAPI.setBookmark(id: note.id, on: target)
            ToastCenter.shared.show(String(localized: target ? "북마크에 넣었어요" : "북마크에서 뺐어요"))
        } catch {
            bookmarked = !target
            ToastCenter.shared.show(String(localized: "북마크를 바꾸지 못했어요"))
        }
    }

    private func toggleConversationMute() async {
        let target = !conversationMuted
        conversationMuted = target
        do {
            _ = try await NoteAPI.setConversationMuted(id: note.id, on: target)
            ToastCenter.shared.show(String(localized: target
                ? "이 대화의 알림을 껐어요"
                : "이 대화의 알림을 다시 받아요"))
        } catch {
            conversationMuted = !target
            ToastCenter.shared.show(String(localized: "대화 알림을 바꾸지 못했어요"))
        }
    }

    private func askLogin(_ message: LocalizedStringKey) {
        loginMessage = message
        showLoginSheet = true
    }

    private var replyAccess: NoteReplyAccess {
        NoteReplyAccess(note, signedIn: AuthStore.shared.isSignedIn)
    }

    private var replyButton: some View {
        let access = replyAccess
        return Button(action: startReply) {
            HStack(spacing: 4) {
                NoteGlyphView(glyph: .reply, size: Self.actionBox * unit)
                if note.replyCount > 0 { Text("\(note.replyCount)").monospacedDigit() }
            }
            .typeScale(.lede)
            .foregroundStyle(access.isClosed ? Palette.faint : Palette.ink)
            .expandTapTarget()
        }
        .buttonStyle(.plain)
        .disabled(access.isClosed)
        .accessibilityLabel(Text("답글 쓰기"))
        .accessibilityValue(Text("답글 \(note.replyCount)"))
        .accessibilityHint(access.notice.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityIdentifier("note.replies.\(note.id)")
    }

    private func startReply() {
        switch replyAccess {
        case .open: replying = true
        case .needsSignIn: askLogin("답글을 달려면 로그인하세요")
        case .closed: break
        }
    }

    private func replied(_ reply: Note) {
        if let onReplied {
            onReplied(reply)
            return
        }
        replyPosts += 1
        onChange(note.addingReply())
        NoteReplyToast.show(reply, open: openNoteRoute)
    }

    private func toggleLike() async {
        guard AuthStore.shared.isSignedIn else {
            askLogin("좋아요를 누르려면 로그인하세요")
            return
        }
        let target = !liked
        let previous = likeCount
        withAnimation(.snappy(duration: 0.2)) {
            liked = target
            likeCount = max((likeCount ?? 0) + (target ? 1 : -1), 0)
        }
        do {
            let status = try await NoteAPI.setLike(id: note.id, on: target)
            withAnimation(.snappy(duration: 0.2)) { likeCount = status.likeCount }
        } catch {
            liked = !target
            likeCount = previous
            ToastCenter.shared.show(String(localized: "좋아요를 반영하지 못했어요"))
        }
    }

    private func delete() async {
        do {
            try await NoteAPI.delete(id: note.id)
            onDelete(note.id)
        } catch {
            ToastCenter.shared.show(String(localized: "노트를 삭제하지 못했습니다"))
        }
    }
}

/// 좋아요·리포스트를 켜고 끌 때 아이콘이 한 번 부풀었다 돌아온다.
struct GlyphPop: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        content.phaseAnimator([1.0, 1.22, 1.0], trigger: trigger) { view, scale in
            view.scaleEffect(scale)
        } animation: { _ in
            .snappy(duration: 0.16)
        }
    }
}

/// 인용된 블로그 글 — 인용된 노트 카드와 같은 틀(작성자 · 블로그 글 + 제목).
enum NoteReplyToast {
    static func show(_ reply: Note, open: ((Route) -> Void)?) {
        let message = String(localized: "답글을 올렸어요")
        guard let open else {
            ToastCenter.shared.show(message)
            return
        }
        ToastCenter.shared.show(message, actionLabel: String(localized: "보기")) {
            open(.note(id: reply.id))
        }
    }
}

extension EnvironmentValues {
    @Entry var openNoteRoute: ((Route) -> Void)? = nil
}

extension VerticalAlignment {
    private enum NoteNameLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
    }

    static let noteNameLine = VerticalAlignment(NoteNameLine.self)
}

extension Author {
    var addressedName: String {
        if hasDisplayName, let displayName { return displayName }
        return "@\(username.split(separator: "@").first.map(String.init) ?? username)"
    }
}

struct QuotedPostCard: View {
    let post: QuotedPost
    var excerpt: String? = nil
    var cover: URL? = nil
    var showsAuthor = true
    var readMinutes: Int? = nil
    @ScaledMetric(relativeTo: .headline) private var thumbSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if showsAuthor {
                        Text(post.authorUsername)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text("· 블로그 글")
                            .foregroundStyle(Palette.secondary)
                    } else {
                        Text("블로그 글")
                            .foregroundStyle(Palette.secondary)
                    }
                    if let readMinutes {
                        Text(verbatim: "·")
                            .foregroundStyle(Palette.faint)
                            .accessibilityHidden(true)
                        Text("\(readMinutes)분 읽기")
                            .foregroundStyle(Palette.secondary)
                    }
                    AccessMarks(marks: post.access)
                }
                .typeScale(.meta)
                Text(post.title)
                    .typeScale(.note)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                if let excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let cover {
                RowThumbnail(url: cover, size: thumbSize)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .stroke(Palette.hairlineStrong, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
    }
}

/// 인용된 노트 — 작성자·시간·글(4줄까지)·사진 줄. 사진은 글 아래 작은 정사각형으로.
struct QuotedNoteCard: View {
    let note: QuotedNote
    /// 글에 실린 노트 — 본문을 자르지 않는다.
    var full = false
    @ScaledMetric(relativeTo: .caption) private var nameCapHalf: CGFloat = 4.4

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .noteNameLine, spacing: 6) {
                AvatarView(author: note.author, size: 20)
                    .alignmentGuide(.noteNameLine) { $0[VerticalAlignment.center] }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ConversationName(author: note.author)
                        .typeScale(.meta)
                    if let date = note.createdAt {
                        Text(date.relativeCompact)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                .alignmentGuide(.noteNameLine) { $0[.firstTextBaseline] - nameCapHalf }
            }
            if let warning = note.contentWarning {
                Text(verbatim: warning)
                    .typeScale(.note)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if !note.body.isEmpty {
                    Text(verbatim: note.body)
                        .typeScale(.note)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .blur(radius: 9)
                        .accessibilityHidden(true)
                }
            } else if !note.body.isEmpty {
                Text(note.body)
                    .typeScale(.note)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(full ? nil : 4)
                    .multilineTextAlignment(.leading)
            }
            if !note.media.isEmpty {
                let concealed = note.contentWarning != nil || note.sensitive == true
                HStack(spacing: 6) {
                    ForEach(note.media) { image in
                        RemoteImage(url: URL(string: image.url), maxPixel: 200) { phase in
                            Palette.hairline
                                .overlay {
                                    if case .success(let loaded) = phase {
                                        loaded.resizable().scaledToFill()
                                            .blur(radius: concealed ? 14 : 0, opaque: true)
                                    }
                                }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusInner))
                        .accessibilityLabel(
                            concealed ? Text("가려진 사진") : Text(image.altText ?? String(localized: "사진")))
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .stroke(Palette.hairlineStrong, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
    }
}

extension QuotedNote {
    init(_ note: Note) {
        self.init(
            id: note.id, body: note.body, createdAt: note.createdAt, author: note.author, media: note.media,
            contentWarning: note.contentWarning, sensitive: note.sensitive)
    }
}

/// 사진 1장은 원래 비율(최대 430pt), 여러 장은 같은 높이로 가로로 넘긴다(스레드 문법). 넘기는 줄은
/// 칼럼 밖 화면 끝까지 그려진다. 대체 텍스트가 곧 접근성 라벨이고, 있으면 ALT 배지로도 드러낸다.
private struct NoteImagesView: View {
    let media: [NoteMedia]
    var concealed = false
    var revealIdentifier: String? = nil
    var reveal: () -> Void = {}
    @State private var opened: NoteMedia?

    private var visual: [NoteMedia] { media.filter { !$0.isAudio } }
    private var audio: [NoteMedia] { media.filter(\.isAudio) }

    var body: some View {
        if !media.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if visual.count == 1, let single = visual.first {
                    tile(single, height: nil)
                } else if !visual.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(visual, id: \.url) { item in
                                tile(item, height: 240)
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .scrollDisabled(concealed)
                    .holdsSwipePager()
                }
                ForEach(audio, id: \.url) { item in
                    NoteAudioRow(media: item)
                }
            }
            .overlay {
                if concealed {
                    Button(action: reveal) {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("가려진 사진"))
                    .accessibilityAction(named: Text("보기"), reveal)
                    .accessibilityIdentifier(revealIdentifier ?? "")
                }
            }
            .padding(.top, 6)
            .fullScreenCover(item: $opened) { item in
                if let url = URL(string: item.url) {
                    if item.isVideo {
                        VideoLightbox(url: url)
                    } else {
                        ImageLightbox(url: url, caption: item.altText)
                    }
                }
            }
        }
    }

    @ViewBuilder private func tile(_ item: NoteMedia, height: CGFloat?) -> some View {
        if item.isVideo, concealed {
            Rectangle()
                .fill(Color.black.opacity(0.88))
                .modifier(TileFrame(ratio: item.ratio ?? 16.0 / 9.0, height: height))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
                .accessibilityHidden(true)
        } else if item.isVideo {
            NoteVideoTile(media: item, height: height) { opened = item }
        } else {
            NoteImageTile(image: item, height: height, concealed: concealed) { opened = item }
        }
    }
}

private struct NoteImageTile: View {
    let image: NoteMedia
    /// nil = 한 장 — 칼럼 폭에 원래 비율로 맞추고 430pt 를 넘지 않는다.
    let height: CGFloat?
    var concealed = false
    let onOpen: () -> Void
    @State private var showAlt = false
    /// 비율은 타일을 만들 때 한 번 정하고 바꾸지 않는다. 지연 스택에서 보이는 행의 높이가 이미지 로드로
    /// 바뀌면 SwiftUI 레이아웃이 끝나지 않아 메인 스레드가 멈췄다.
    @State private var ratio: CGFloat

    private static let maxPixel: CGFloat = 900
    private static let unknownRatio: CGFloat = 4.0 / 3.0
    private var url: URL? { URL(string: image.url) }

    init(image: NoteMedia, height: CGFloat?, concealed: Bool = false, onOpen: @escaping () -> Void) {
        self.image = image
        self.height = height
        self.concealed = concealed
        self.onOpen = onOpen
        _ratio = State(initialValue: image.ratio ?? Self.cachedRatio(image.url) ?? Self.unknownRatio)
    }

    private static func cachedRatio(_ string: String) -> CGFloat? {
        guard let url = URL(string: string),
            let size = RemoteImageCache.shared.cached(url, maxPixel: maxPixel)?.size,
            size.height > 0
        else { return nil }
        return min(max(size.width / size.height, 0.5), 2)
    }

    var body: some View {
        RemoteImage(url: url, maxPixel: Self.maxPixel) { phase in
            Palette.hairline
                .modifier(TileFrame(ratio: ratio, height: height))
                .overlay {
                    if case .success(let loaded) = phase {
                        loaded.resizable().scaledToFill()
                            .overlay {
                                if concealed {
                                    loaded.resizable().scaledToFill()
                                        .blur(radius: 36, opaque: true)
                                        .transition(.opacity)
                                }
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius).stroke(Palette.hairline, lineWidth: 0.5))
            .overlay(alignment: .bottomLeading) { if !concealed { altLayer } }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
            .onTapGesture(perform: onOpen)
            .accessibilityElement()
            .accessibilityAddTraits([.isImage, .isButton])
            .accessibilityLabel(Text(image.altText ?? String(localized: "사진")))
            .accessibilityHint(Text("두 번 탭하면 크게 봅니다"))
            .accessibilityHidden(concealed)
        }
    }

    @ViewBuilder private var altLayer: some View {
        if let alt = image.altText, !alt.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if showAlt {
                    Text(alt)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    showAlt.toggle()
                } label: {
                    Text(verbatim: "ALT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(GlassTokens.mediaChip, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("사진 설명 보기")
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottom) {
                if showAlt {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        }
    }
}

struct TileFrame: ViewModifier {
    let ratio: CGFloat
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(width: height * ratio, height: height)
        } else {
            content
                .aspectRatio(max(ratio, 0.8), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 430, alignment: .leading)
        }
    }
}

/// 본문 안의 http(s) 주소와 #해시태그를 링크로 — 웹·서버와 같은 규칙(끝 문장부호는 링크에서 뺀다).
enum NoteText {
    private static let urlPattern = try? NSRegularExpression(pattern: "https?://[^\\s<]+")
    private static let tokenPattern = try? NSRegularExpression(
        pattern: "(https?://[^\\s<]+)|(?<![=/)\\p{L}\\p{M}\\p{N}_#])#([\\p{L}\\p{M}\\p{N}_][\\p{L}\\p{M}\\p{N}_·・]*)"
            + "|(?<![A-Za-z0-9_])@([A-Za-z0-9][A-Za-z0-9_]{2,15})(?![A-Za-z0-9_@])")
    private static let trailing = CharacterSet(charactersIn: ".,!?:;)]'\"")
    private static let tagSeparators = CharacterSet(charactersIn: "·・")
    private static let linkScheme = "kurl-note"
    /// "#" 와 한글 태그 사이는 줄바꿈 자리라 "#" 만 줄 끝에 남는다 — 표시에만 넣고 보낼 땐 plain 으로 뺀다.
    static let tagJoiner = "\u{2060}"

    static func attributed(_ body: String, mentions: [String] = [], tags: Bool = true) -> AttributedString {
        let members = Set(mentions)
        var result = AttributedString()
        let ns = body as NSString
        var last = 0
        for match in tokenPattern?.matches(in: body, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let text: String
            let url: URL?
            var consumed: Int?
            if match.range(at: 1).location != NSNotFound {
                var link = ns.substring(with: match.range(at: 1))
                while let scalar = link.unicodeScalars.last, trailing.contains(scalar) {
                    link.removeLast()
                }
                text = link
                url = URL(string: link)
            } else if match.range(at: 2).location != NSNotFound {
                guard tags, let name = tagName(ns.substring(with: match.range(at: 2))) else { continue }
                text = "#" + tagJoiner + name
                url = link(.tag(name))
                consumed = 1 + (name as NSString).length
            } else {
                let handle = ns.substring(with: match.range(at: 3))
                guard members.contains(handle.lowercased()) else { continue }
                text = "@" + handle
                url = link(.member(handle.lowercased()))
            }
            if match.range.location > last {
                result += AttributedString(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            }
            var part = AttributedString(text)
            part.link = url
            result += part
            last = match.range.location + (consumed ?? (text as NSString).length)
        }
        if last < ns.length { result += AttributedString(ns.substring(from: last)) }
        return result
    }

    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: tagJoiner, with: "")
    }

    static func tokenRanges(in body: String) -> [NSRange] {
        let ns = body as NSString
        return tokenPattern?.matches(in: body, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
    }

    static func tagName(_ raw: String) -> String? {
        var name = raw
        while let scalar = name.unicodeScalars.last, tagSeparators.contains(scalar) {
            name.removeLast()
        }
        guard (name as NSString).length <= 40,
              name.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && !CharacterSet.nonBaseCharacters.contains($0) })
        else { return nil }
        return name
    }

    static func link(_ target: NoteLinkTarget) -> URL? {
        var components = URLComponents()
        components.scheme = linkScheme
        switch target {
        case let .tag(name):
            components.host = "tag"
            components.path = "/" + name
        case let .member(username):
            components.host = "member"
            components.path = "/" + username
        }
        return components.url
    }

    static func target(from url: URL) -> NoteLinkTarget? {
        guard url.scheme == linkScheme else { return nil }
        let value = String(url.path(percentEncoded: false).dropFirst())
        guard !value.isEmpty else { return nil }
        switch url.host() {
        case "tag": return .tag(value)
        case "member": return .member(value)
        default: return nil
        }
    }

    static func length(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    /// 링크 카드가 다룰 주소 — 첫 주소, 서버·웹과 같은 규칙. 사진이나 인용이 있으면 카드가 없다.
    static func previewUrl(_ body: String, hasMedia: Bool, hasQuote: Bool) -> String? {
        guard !hasMedia, !hasQuote else { return nil }
        let ns = body as NSString
        guard let match = urlPattern?.firstMatch(in: body, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        var link = ns.substring(with: match.range)
        while let scalar = link.unicodeScalars.last, trailing.contains(scalar) {
            link.removeLast()
        }
        return link.count <= 2048 ? link : nil
    }
}

/// 노트 링크 카드 — 사진이 있으면 1.91:1로 위에, 아래로 도메인 · 제목(2줄). 사진이 없으면 설명 2줄.
struct NoteLinkCardView: View {
    let preview: NoteLinkPreview

    private var domain: String {
        guard let host = URL(string: preview.url)?.host() else { return preview.url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = preview.image.flatMap(URL.init(string:)) {
                Palette.hairline
                    .aspectRatio(1.91, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: image, maxPixel: 900) { phase in
                            if case .success(let loaded) = phase {
                                loaded.resizable().scaledToFill()
                            }
                        }
                    }
                    .clipped()
                    .overlay(alignment: .bottom) { Hairline() }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(domain)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                if let title = preview.title {
                    Text(title)
                        .typeScale(.note)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if preview.image == nil, let description = preview.description {
                    Text(description)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).stroke(Palette.hairlineStrong, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
    }
}

/// 피드의 노트 한 줄 — 작성자가 이어 쓴 노트면 둘째 편을 스레드 선으로 잇고, 셋 이상이면
/// 나머지는 "이어지는 글 N개 더"로 상세에 맡긴다(스레드·X와 같다).
struct NoteFeedItem: View {
    let note: Note
    let onChange: (Note) -> Void
    let onDelete: (Int64) -> Void
    var onQuoted: ((Note) -> Void)? = nil
    var repostedBy: String? = nil
    var showsPin = false
    var replyHeader: ReplyHeader? = nil

    var body: some View {
        let thread = note.thread
        let next = thread?.preview.first
        VStack(alignment: .leading, spacing: 0) {
            NoteRowView(
                note: note,
                onChange: { updated in
                    var kept = updated
                    if kept.thread == nil { kept.thread = note.thread }
                    onChange(kept)
                },
                onDelete: onDelete, onQuoted: onQuoted, repostedBy: repostedBy, showsPin: showsPin,
                replyHeader: replyHeader,
                threadLineBelow: next != nil,
                position: next == nil ? nil : thread.map { "1/\($0.total)" })
            if let thread, let next {
                NoteRowView(
                    note: next,
                    onChange: { updated in
                        var parent = note
                        parent.thread = NoteSelfThread(total: thread.total, preview: [updated])
                        onChange(parent)
                    },
                    onDelete: { _ in
                        var parent = note
                        parent.thread = nil
                        onChange(parent)
                    },
                    onQuoted: onQuoted,
                    position: "2/\(thread.total)")
                if thread.total > 2 {
                    NavigationLink(value: Route.note(id: note.id)) {
                        Text("이어지는 글 \(thread.total - 2)개 더")
                            .typeScale(.meta)
                            .fontWeight(.medium)
                            .foregroundStyle(Palette.ink)
                            .padding(.leading, 48)
                            .padding(.bottom, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.threadMore.\(note.id)")
                }
            }
        }
    }
}

/// 노트 상세 — 원글(답글이면) · 노트 · 답글. 답글은 툴바 버튼이 여는 작성 시트로.
struct NoteDetailView: View {
    let noteId: Int64
    @State private var thread: NoteThread?
    @State private var failed: String?
    @State private var replying = false
    @State private var deleted = false
    @State private var showLoginSheet = false
    @State private var replied = 0
    @State private var landed: Int64?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openNoteRoute) private var openNoteRoute

    var body: some View {
        Group {
            if let thread {
                ScrollViewReader { proxy in
                    ScrollView {
                        content(thread)
                    }
                    .brandRefreshable { await load() }
                    .onChange(of: landed) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                            proxy.scrollTo(id)
                        }
                        landed = nil
                    }
                }
            } else if let failed {
                ErrorState(message: failed, retry: { Task { await load() } })
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                KurlLoadingMark().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.readingBg)
        .navigationTitle("노트")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.readingBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .noteTextLinks()
        .hidesTabBar()
        .safeAreaInset(edge: .bottom) {
            if let thread { replyBar(to: thread.note) }
        }
        .sheet(isPresented: $replying) {
            if let note = thread?.note {
                NoteComposeSheet(mode: .reply(note)) { land($0) }
            }
        }
        .sensoryFeedback(.success, trigger: replied)
        .loginPrompt(isPresented: $showLoginSheet, message: "답글을 달려면 로그인하세요")
        .task { if thread == nil { await load() } }
    }

    private func content(_ thread: NoteThread) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let trail = thread.series {
                // 시리즈 속 노트 — 글 상세와 같은 자리에서 "여정의 몇 번째"부터 세운다.
                AnyView(
                    SeriesBanner(
                        nav: trail, username: thread.note.author.username,
                        currentId: "note-\(thread.note.id)")
                        .padding(.top, 12)
                        .padding(.bottom, 8))
            }
            if let parent = thread.parent {
                NoteRowView(
                    note: parent,
                    onChange: { next in update { $0.parent = next } },
                    onDelete: { _ in update { $0.parent = nil } },
                    threadLineBelow: true,
                    onReplied: land)
            }
            let parts = thread.continuation ?? []
            let numbered = !parts.isEmpty && thread.parent?.author.id != thread.note.author.id
            NoteRowView(
                note: thread.note,
                onChange: { note in update { $0.note = note } },
                onDelete: { _ in dismiss() },
                focused: true,
                position: numbered ? "1/\(parts.count + 1)" : nil,
                onReplied: land)
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                NoteRowView(
                    note: part,
                    onChange: { next in update { $0.continuation = $0.continuation?.map { $0.id == next.id ? next : $0 } } },
                    onDelete: { id in update { $0.continuation?.removeAll { $0.id == id } } },
                    threadLineBelow: index < parts.count - 1,
                    position: numbered ? "\(index + 2)/\(parts.count + 1)" : nil,
                    onReplied: land)
                    .environment(\.insideRoom, thread.note.room?.id)
                    .id(part.id)
            }
            if let trail = thread.series {
                AnyView(
                    SeriesNextCard(nav: trail, username: thread.note.author.username)
                        .padding(.bottom, 14))
            }
            Hairline().padding(.horizontal, -Metrics.noteGutter)
            let replies = thread.replies.filter {
                NoteFilterStore.shared.verdict(for: $0, in: .thread) != .hide
            }
            if !thread.replies.isEmpty {
                HStack(spacing: 6) {
                    Text("답글")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: "\(thread.replies.count)")
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
                .typeScale(.note)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                NoteRowView(
                    note: reply,
                    onChange: { next in update { $0.replies = $0.replies.map { $0.id == next.id ? next : $0 } } },
                    onDelete: { id in update { $0.replies.removeAll { $0.id == id } } },
                    onReplied: land)
                    .environment(\.noteFilterContext, .thread)
                    .environment(\.insideRoom, thread.note.room?.id)
                    .id(reply.id)
                if index < replies.count - 1 {
                    Hairline().padding(.horizontal, -Metrics.noteGutter)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: Metrics.readingColumn)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.noteGutter)
    }

    @ViewBuilder private func replyBar(to note: Note) -> some View {
        let access = NoteReplyAccess(note, signedIn: AuthStore.shared.isSignedIn)
        Group {
            if let notice = access.notice {
                Text(notice)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("note.replyClosed")
            } else {
                Button {
                    if access == .open { replying = true } else { showLoginSheet = true }
                } label: {
                    ReplyPrompt(text: Text("\(note.author.addressedName)님에게 답글 남기기"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("답글 쓰기"))
                .accessibilityIdentifier("note.reply")
            }
        }
        .padding(.horizontal, Metrics.noteGutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: Metrics.readingColumn)
        .frame(maxWidth: .infinity)
        .background(Palette.readingBg)
        .overlay(alignment: .top) { Hairline() }
    }

    private func land(_ reply: Note) {
        guard let thread else { return }
        let placed = thread.adding(reply)
        self.thread = placed.thread
        replied += 1
        if placed.landing == .elsewhere {
            NoteReplyToast.show(reply, open: openNoteRoute)
        } else {
            landed = reply.id
        }
    }

    private func update(_ change: (inout NoteThread) -> Void) {
        guard var next = thread else { return }
        change(&next)
        thread = next
    }

    private func load() async {
        do {
            let fresh = try await NoteAPI.thread(id: noteId)
            thread = fresh
            failed = nil
            if fresh.series != nil { PostReadStore.notes.markRead(noteId) }
        } catch let error as APIError where error.statusCode == 404 {
            thread = nil
            failed = String(localized: "볼 수 없는 노트예요")
        } catch {
            if thread == nil {
                failed = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }
}

/// 노트 작성·고치기 시트. 새 노트는 사진(최대 4장, 장마다 대체 텍스트)과 블로그 글 인용을 받는다.
/// 처음 올릴 때 한 번, 다른 서버로 퍼진 사본은 지운다는 보장을 못 한다는 안내를 확인받는다.
struct NoteComposeSheet: View {
    enum Mode {
        case new(quote: QuotedPost?, inReplyToId: Int64?)
        case reply(Note)
        case quote(QuotedNote)
        case edit(Note)
    }

    private struct PickedImage: Identifiable {
        let id = UUID()
        let image: UIImage
        let upload: NoteUploadImage
        var altText = ""
    }

    private struct AltTarget: Identifiable {
        let id: UUID
    }

    private struct ThreadPart: Identifiable {
        let id = UUID()
        var text = ""
    }

    let mode: Mode
    let onLongForm: ((String) -> Void)?
    let onDone: (Note) -> Void
    let fixedRoom: NoteRoom?

    @State private var text: String
    @State private var destination: NoteRoom?
    @State private var rooms: [RoomListItem] = []
    @State private var warning: String
    @State private var warns: Bool
    @State private var sensitive: Bool
    /// nil = 답글이면 원글과 같은 범위(서버가 이어받는다), 아니면 공개.
    @State private var visibility: NoteVisibility?
    @State private var quote: QuotedPost?
    @State private var picked: [PickedImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var takingPhoto = false
    @State private var posting = false
    @State private var showNotice = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    @State private var altTarget: AltTarget?
    @State private var linkCard: NoteLinkPreview?
    @State private var poll: NotePollDraft?
    @State private var scheduledAt: Date?
    @State private var language = NoteLanguages.posting
    @State private var pickingSchedule = false
    @State private var parts: [ThreadPart] = []
    @State private var confirmLongForm = false
    @FocusState private var focused: Bool
    @FocusState private var focusedPart: UUID?
    @AccessibilityFocusState private var targetFocused: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dismiss) private var dismiss

    init(
        mode: Mode, room: NoteRoom? = nil, suggestedRoom: NoteRoom? = nil,
        onLongForm: ((String) -> Void)? = nil, onDone: @escaping (Note) -> Void
    ) {
        self.mode = mode
        self.onLongForm = onLongForm
        self.onDone = onDone
        self.fixedRoom = room
        _destination = State(initialValue: room ?? suggestedRoom)
        switch mode {
        case let .new(quote, _):
            _text = State(initialValue: "")
            _quote = State(initialValue: quote)
        case .reply, .quote:
            _text = State(initialValue: "")
            _quote = State(initialValue: nil)
        case let .edit(note):
            _text = State(initialValue: note.body)
            _quote = State(initialValue: nil)
        }
        let editing: Note? = if case let .edit(note) = mode { note } else { nil }
        _warning = State(initialValue: editing?.contentWarning ?? "")
        _warns = State(initialValue: editing?.contentWarning != nil)
        _sensitive = State(initialValue: editing?.sensitive == true && editing?.contentWarning == nil)
        _visibility = State(initialValue: editing?.noteVisibility)
    }

    private var isEdit: Bool { if case .edit = mode { true } else { false } }

    private var picksDestination: Bool {
        if case .new(_, nil) = mode { fixedRoom == nil && AuthStore.shared.isSignedIn } else { false }
    }

    @ViewBuilder
    private var destinationChip: some View {
        if let fixedRoom {
            Text(fixedRoom.name)
                .typeScale(.note)
                .fontWeight(.semibold)
                .accessibilityIdentifier("noteCompose.room")
        } else if picksDestination {
            Menu {
                Button("내 노트") { destination = nil }
                ForEach(rooms) { room in
                    Button(room.name) {
                        destination = NoteRoom(id: room.id, name: room.name)
                        scheduledAt = nil
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(destination?.name ?? String(localized: "내 노트"))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .typeScale(.note)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.ink)
            }
            .accessibilityIdentifier("noteCompose.destination")
        }
    }
    private var inReplyToId: Int64? {
        switch mode {
        case let .new(_, id): id
        case let .reply(target): target.id
        case .quote, .edit: nil
        }
    }
    private var replyTarget: Note? { if case let .reply(target) = mode { target } else { nil } }
    private var quotedNote: QuotedNote? { if case let .quote(note) = mode { note } else { nil } }
    private var length: Int { NoteText.length(text) }
    private var cardUrl: String? {
        isEdit
            ? nil
            : NoteText.previewUrl(
                text, hasMedia: !picked.isEmpty || poll != nil, hasQuote: quote != nil || quotedNote != nil)
    }
    private var placeholder: LocalizedStringKey {
        if quotedNote != nil { return "생각 덧붙이기" }
        return inReplyToId == nil ? "노트 쓰기" : "답글 쓰기"
    }
    private var title: LocalizedStringKey {
        if isEdit { return "노트 고치기" }
        if quotedNote != nil { return "노트 인용" }
        return inReplyToId == nil ? "새 노트" : "답글"
    }
    private var hasImages: Bool {
        if case let .edit(note) = mode { return !note.media.isEmpty }
        return !picked.isEmpty
    }
    private var warningText: String { warns ? warning.trimmingCharacters(in: .whitespacesAndNewlines) : "" }
    private var canPost: Bool {
        !posting && length <= NoteAPI.maxLength && (length > 0 || hasImages)
            && NoteText.length(warningText) <= NoteAPI.maxWarningLength
            && (poll == nil || (poll?.isValid == true && length > 0))
            && parts.allSatisfy { NoteText.length($0.text) <= NoteAPI.maxLength }
    }
    /// 스레드 이어 쓰기 — 고치기·예약에선 쓸 수 없다(서버가 예약 스레드를 받지 않는다).
    private var canAddPart: Bool {
        !isEdit && inReplyToId == nil && scheduledAt == nil && parts.count < NoteAPI.maxThreadNotes - 1
    }
    private var discardTitle: LocalizedStringKey {
        isEdit ? "고친 내용을 버릴까요?" : "작성 중인 노트를 버릴까요?"
    }
    private var hasDraft: Bool {
        if case let .edit(note) = mode {
            return text != note.body || warningText != (note.contentWarning ?? "")
                || sensitive != (note.sensitive == true && note.contentWarning == nil)
        }
        return length > 0 || !picked.isEmpty || !warningText.isEmpty || poll != nil
            || parts.contains { NoteText.length($0.text) > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let replyTarget { targetRow(replyTarget) }
                    HStack(alignment: .top, spacing: 12) {
                        threadColumn(size: 36, line: !parts.isEmpty || canAddPart)
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let name = AuthStore.shared.me?.username {
                                    Text(name)
                                        .typeScale(.note)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Palette.ink)
                                }
                                if warns {
                                    TextField("열람 주의 문구", text: $warning, axis: .vertical)
                                        .typeScale(.note)
                                        .fontWeight(.medium)
                                        .lineLimit(1...3)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radius))
                                        .padding(.vertical, 4)
                                        .accessibilityIdentifier("noteCompose.warning")
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                TextField(placeholder, text: $text, axis: .vertical)
                                    .typeScale(.note)
                                    .lineLimit(1...20)
                                    .focused($focused)
                                    .accessibilityIdentifier("noteCompose.text")
                                if focused {
                                    MentionSuggestionList(
                                        query: MentionDraft.trailingQuery(in: text, allowingServer: true),
                                        onPick: {
                                            text = MentionDraft.complete(
                                                text, with: $0.username, allowingServer: true)
                                        },
                                        onPickRemote: {
                                            text = MentionDraft.complete(text, with: $0.acct, allowingServer: true)
                                        })
                                }
                            }
                            if let draft = Binding($poll) {
                                NotePollEditor(draft: draft)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            if !picked.isEmpty { pickedStrip }
                            if let quote { quoteCard(quote) }
                            if let quotedNote { QuotedNoteCard(note: quotedNote) }
                            if let linkCard, linkCard.url == cardUrl {
                                NoteLinkCardView(preview: linkCard)
                                    .accessibilityIdentifier("noteCompose.linkCard")
                            }
                            if let errorMessage {
                                Text(errorMessage)
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.danger)
                                    .fontWeight(.semibold)
                            }
                            HStack(spacing: 14) {
                            if !isEdit {
                                PhotosPicker(
                                    selection: $pickerItems,
                                    maxSelectionCount: max(0, NoteAPI.maxImages - picked.count),
                                    matching: .images
                                ) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(
                                            picked.count >= NoteAPI.maxImages || poll != nil ? Palette.faint : Palette.secondary)
                                        .frame(width: 32, height: 28, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .disabled(picked.count >= NoteAPI.maxImages || poll != nil)
                                .accessibilityLabel("사진 추가")
                                if NoteCamera.isAvailable {
                                    Button {
                                        takingPhoto = true
                                    } label: {
                                        Image(systemName: "camera")
                                            .font(.system(size: 18))
                                            .foregroundStyle(
                                                picked.count >= NoteAPI.maxImages || poll != nil ? Palette.faint : Palette.secondary)
                                            .frame(width: 32, height: 28, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .disabled(picked.count >= NoteAPI.maxImages || poll != nil)
                                    .accessibilityLabel("사진 찍기")
                                    .accessibilityIdentifier("noteCompose.camera")
                                }
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        poll = poll == nil ? NotePollDraft() : nil
                                    }
                                } label: {
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.system(size: 17))
                                        .foregroundStyle(
                                            poll != nil ? Palette.ink : picked.isEmpty ? Palette.secondary : Palette.faint)
                                        .frame(width: 32, height: 28, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!picked.isEmpty)
                                .accessibilityLabel(poll == nil ? "투표 추가" : "투표 빼기")
                                .accessibilityIdentifier("noteCompose.pollToggle")
                            }
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) { warns.toggle() }
                                } label: {
                                    Text("열람 주의")
                                        .typeScale(.meta)
                                        .fontWeight(warns ? .semibold : .regular)
                                        .foregroundStyle(warns ? Palette.ink : Palette.secondary)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .frame(minHeight: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(warns ? .isSelected : [])
                                .accessibilityIdentifier("noteCompose.warningToggle")
                                if hasImages, !warns {
                                    Button {
                                        sensitive.toggle()
                                    } label: {
                                        Image(systemName: sensitive ? "eye.half.closed.fill" : "eye.half.closed")
                                            .font(.system(size: 17))
                                            .foregroundStyle(sensitive ? Palette.ink : Palette.secondary)
                                            .frame(width: 32, height: 28, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(sensitive ? "민감한 사진 표시 끄기" : "민감한 사진으로 표시")
                                    .accessibilityIdentifier("noteCompose.sensitiveToggle")
                                }
                                if onLongForm != nil, !longFormBody.isEmpty {
                                    Spacer(minLength: 0)
                                    Button("긴 글로 옮기기", systemImage: "doc.text") { confirmLongForm = true }
                                        .typeScale(.meta)
                                        .foregroundStyle(Palette.secondary)
                                        .buttonStyle(.plain)
                                        .frame(minHeight: 28)
                                        .accessibilityIdentifier("noteCompose.longForm")
                                }
                            }
                        }
                        .padding(.bottom, !parts.isEmpty || canAddPart ? 14 : 0)
                    }
                    ForEach($parts) { $part in
                        partRow($part, last: part.id == parts.last?.id)
                    }
                    if canAddPart { addPartRow }
                }
                .padding(Metrics.gutter)
                .alert(discardTitle, isPresented: $confirmDiscard) {
                    Button("버리기", role: .destructive) { dismiss() }
                    Button("계속 쓰기", role: .cancel) {}
                }
                .confirmationDialog("긴 글로 옮길까요?", isPresented: $confirmLongForm, titleVisibility: .visible) {
                    Button("긴 글로 옮기기", action: handOffLongForm)
                } message: {
                    Text(
                        picked.isEmpty && poll == nil
                            ? "쓴 내용이 새 글 본문으로 옮겨져요."
                            : "쓴 내용이 새 글 본문으로 옮겨져요. 사진과 투표는 옮겨지지 않아요.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.sheetBg)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if hasDraft { confirmDiscard = true } else { dismiss() }
                    }
                }
                if fixedRoom != nil || picksDestination {
                    ToolbarItem(placement: .principal) { destinationChip }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if posting {
                            ProgressView()
                        } else {
                            if let destination, !isEdit, scheduledAt == nil {
                                Text("\(destination.name)에 올리기")
                                    .lineLimit(1)
                            } else {
                                Text(
                                    isEdit
                                        ? LocalizedStringKey("저장")
                                        : scheduledAt == nil ? LocalizedStringKey("올리기") : LocalizedStringKey("예약"))
                            }
                        }
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(GlassTokens.prominentTint)
                    .disabled(!canPost)
                    .accessibilityIdentifier("noteCompose.post")
                }
            }
            .sheet(item: $altTarget) { target in
                altEditor(for: target.id)
            }
            .task {
                guard picksDestination else { return }
                rooms = (try? await RoomAPI.mine()) ?? []
            }
            .sheet(isPresented: $pickingSchedule) {
                NoteScheduleSheet(initial: scheduledAt) { picked in
                    withAnimation(.snappy(duration: 0.2)) { scheduledAt = picked }
                }
            }
            .alert("노트는 다른 서버에도 전해져요", isPresented: $showNotice) {
                Button("알겠어요, 올릴게요") {
                    Task {
                        try? await NoteAPI.updateFederationSettings(noticeSeen: true)
                        await post()
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("kurl 노트는 마스토돈·Misskey 같은 다른 서버의 팔로워에게도 전해져요. 노트를 지우면 그 서버들에도 지우라고 알리지만, 이미 퍼진 사본이 지워진다는 보장은 할 수 없어요. 설정에서 언제든 끌 수 있어요.")
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPicked(items) }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                NoteCamera { photo in
                    guard let data = photo.jpegData(compressionQuality: 0.95) else { return }
                    Task { await attach(data) }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                if replyTarget != nil, voiceOver {
                    Task { @MainActor in targetFocused = true }
                } else {
                    focused = true
                }
            }
            .task(id: cardUrl) { await loadLinkCard() }
        }
        .interactiveDismissDisabled(posting || hasDraft)
    }

    private var longFormBody: String {
        ([text] + parts.map(\.text))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func handOffLongForm() {
        onLongForm?(longFormBody)
        dismiss()
    }

    private var shownVisibility: NoteVisibility { visibility ?? .public }

    @ViewBuilder private var visibilityLabel: some View {
        HStack(spacing: 6) {
            if visibility == nil, inReplyToId != nil {
                Text("원글과 같은 범위")
                    .typeScale(.meta)
            } else {
                Text(shownVisibility == .public ? shownVisibility.detail : shownVisibility.title)
                    .typeScale(.meta)
            }
            if !isEdit {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let destination {
                Text("\(destination.name) 멤버만 볼 수 있어요")
                    .typeScale(.meta)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("noteCompose.roomAudience")
            } else if isEdit {
                visibilityLabel
            } else {
                Menu {
                    Picker("공개 범위", selection: $visibility) {
                        if inReplyToId != nil {
                            Label("원글과 같은 범위", systemImage: "arrowshape.turn.up.left")
                                .tag(NoteVisibility?.none)
                        }
                        ForEach(NoteVisibility.allCases) { option in
                            Label {
                                Text(option.title)
                                Text(option.detail)
                            } icon: {
                                Image(systemName: option.symbol)
                            }
                            .tag(NoteVisibility?.some(option))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    visibilityLabel
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("noteCompose.visibility")
                Menu {
                    Picker("언어", selection: $language) {
                        ForEach(NoteLanguages.all) { option in
                            Text(verbatim: option.name).tag(option.code)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(verbatim: language.uppercased())
                        .typeScale(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("언어"))
                .accessibilityValue(Text(verbatim: NoteLanguages.name(language)))
                .accessibilityIdentifier("noteCompose.language")
                if parts.isEmpty, inReplyToId == nil, destination == nil {
                    Button {
                        pickingSchedule = true
                    } label: {
                        HStack(spacing: 4) {
                            if let scheduledAt {
                                Image(systemName: "clock.fill")
                                Text(scheduledAt, format: .dateTime.month().day().hour().minute())
                            } else {
                                Text("예약")
                            }
                        }
                        .typeScale(.meta)
                        .foregroundStyle(scheduledAt == nil ? Palette.secondary : Palette.ink)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(scheduledAt == nil ? Text("예약") : Text("예약 시각 바꾸기"))
                    .accessibilityIdentifier("noteCompose.schedule")
                }
            }
            Spacer(minLength: 0)
            if length > 0 {
                NoteLengthRing(length: length, limit: NoteAPI.maxLength)
            }
        }
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Palette.sheetBg)
        .overlay(alignment: .top) { Hairline() }
    }

    @ViewBuilder private func myAvatar(size: CGFloat) -> some View {
        if let me = AuthStore.shared.me {
            AvatarView(
                author: Author(id: me.id ?? 0, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl),
                size: size)
        }
    }

    private func targetRow(_ target: Note) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                AvatarView(author: target.author, size: 36)
                Capsule()
                    .fill(Palette.hairlineStrong)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                ConversationName(author: target.author)
                    .typeScale(.note)
                targetExcerpt(target)
                    .typeScale(.note)
                    .foregroundStyle(target.contentWarning == nil ? Palette.ink : Palette.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            .accessibilityFocused($targetFocused)
            .accessibilityIdentifier("noteCompose.replyTarget")
        }
    }

    private func targetExcerpt(_ target: Note) -> Text {
        if let warning = target.contentWarning { return Text(verbatim: warning) }
        if !target.body.isEmpty { return Text(verbatim: target.body) }
        if !target.media.isEmpty { return Text("사진 \(target.media.count)장") }
        return Text(verbatim: "")
    }

    /// 아바타 아래로 다음 노트까지 잇는 스레드 선 — 스레드 작성 화면과 같은 문법.
    private func threadColumn(size: CGFloat, line: Bool) -> some View {
        VStack(spacing: 4) {
            myAvatar(size: size)
            if line {
                Capsule()
                    .fill(Palette.hairlineStrong)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 36)
    }

    private func partRow(_ part: Binding<ThreadPart>, last: Bool) -> some View {
        let count = NoteText.length(part.wrappedValue.text)
        let id = part.wrappedValue.id
        return HStack(alignment: .top, spacing: 12) {
            threadColumn(size: 28, line: !last || canAddPart)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let name = AuthStore.shared.me?.username {
                        Text(name)
                            .typeScale(.note)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                    }
                    Spacer(minLength: 0)
                    if count > NoteAPI.maxLength - 100 {
                        NoteLengthRing(length: count, limit: NoteAPI.maxLength)
                    }
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { parts.removeAll { $0.id == id } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("이 노트 빼기")
                }
                TextField("스레드 이어 쓰기", text: part.text, axis: .vertical)
                    .typeScale(.note)
                    .lineLimit(1...20)
                    .focused($focusedPart, equals: id)
                    .accessibilityIdentifier("noteCompose.part")
                if focusedPart == id {
                    MentionSuggestionList(
                        query: MentionDraft.trailingQuery(in: part.wrappedValue.text, allowingServer: true),
                        onPick: {
                            part.wrappedValue.text = MentionDraft.complete(
                                part.wrappedValue.text, with: $0.username, allowingServer: true)
                        },
                        onPickRemote: {
                            part.wrappedValue.text = MentionDraft.complete(
                                part.wrappedValue.text, with: $0.acct, allowingServer: true)
                        })
                }
            }
            .padding(.bottom, 14)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var addPartRow: some View {
        Button {
            let next = ThreadPart()
            withAnimation(.snappy(duration: 0.2)) { parts.append(next) }
            Task { @MainActor in focusedPart = next.id }
        } label: {
            HStack(spacing: 12) {
                myAvatar(size: 20)
                    .opacity(0.45)
                    .frame(width: 36)
                Text("스레드에 추가")
                    .typeScale(.note)
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("noteCompose.addPart")
    }

    private var pickedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(picked) { item in
                    let ratio = min(max(item.image.size.width / max(item.image.size.height, 1), 0.5), 1.8)
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 190 * ratio, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
                        .accessibilityLabel(Text(item.altText.isEmpty ? String(localized: "사진") : item.altText))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { picked.removeAll { $0.id == item.id } }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(GlassTokens.mediaChip, in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .accessibilityLabel("사진 빼기")
                        }
                        .overlay(alignment: .bottomLeading) {
                            Button {
                                altTarget = AltTarget(id: item.id)
                            } label: {
                                HStack(spacing: 3) {
                                    Text(verbatim: item.altText.isEmpty ? "+ALT" : "ALT")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(GlassTokens.mediaChip, in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .accessibilityLabel("대체 텍스트 추가")
                        }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func quoteCard(_ quote: QuotedPost) -> some View {
        QuotedPostCard(post: quote)
            .overlay(alignment: .topTrailing) {
                Button {
                    self.quote = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.faint)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("인용 빼기")
            }
    }

    private func altEditor(for id: UUID) -> some View {
        let binding = Binding(
            get: { picked.first { $0.id == id }?.altText ?? "" },
            set: { value in
                if let index = picked.firstIndex(where: { $0.id == id }) { picked[index].altText = value }
            })
        return NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let image = picked.first(where: { $0.id == id })?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
                        .accessibilityHidden(true)
                }
                TextField("대체 텍스트", text: binding, axis: .vertical)
                    .typeScale(.body)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("noteCompose.alt")
                Text("사진을 설명해 주세요. 화면 낭독기가 읽어요")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
            }
            .padding(Metrics.gutter)
            .navigationTitle("대체 텍스트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { altTarget = nil }
                        .tint(Palette.link)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadLinkCard() async {
        guard let url = cardUrl else {
            linkCard = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let fetched = try? await NoteAPI.linkPreview(url: url)
        guard !Task.isCancelled else { return }
        linkCard = fetched.flatMap { $0.title != nil || $0.image != nil ? $0 : nil }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            await attach(data)
        }
        pickerItems = []
    }

    private func attach(_ data: Data) async {
        guard picked.count < NoteAPI.maxImages,
              let upload = await NoteUploadImage.prepare(data),
              let image = UIImage(data: upload.data)
        else { return }
        picked.append(PickedImage(image: image, upload: upload))
    }

    private func submit() async {
        guard canPost else { return }
        if case let .edit(note) = mode {
            posting = true
            defer { posting = false }
            do {
                onDone(try await NoteAPI.edit(
                    id: note.id, body: NoteText.plain(text), contentWarning: warningText, sensitive: sensitive))
                dismiss()
            } catch {
                errorMessage = String(localized: "노트를 고치지 못했어요")
            }
            return
        }
        let needsNotice: Bool
        if let settings = try? await NoteAPI.federationSettings() {
            needsNotice = settings.enabled && !settings.noticeSeen
        } else {
            needsNotice = true
        }
        if needsNotice {
            showNotice = true
        } else {
            await post()
        }
    }

    private func post() async {
        posting = true
        defer { posting = false }
        errorMessage = nil
        do {
            var images: [NoteDraft.Image] = []
            for item in picked {
                let key = try await NoteAPI.uploadImage(item.upload)
                images.append(NoteDraft.Image(
                    key: key, altText: item.altText, width: item.upload.pixelWidth, height: item.upload.pixelHeight))
            }
            let draft = NoteDraft(
                body: NoteText.plain(text), images: images, quotedPostId: quote?.id, inReplyToId: inReplyToId,
                quotedNoteId: quotedNote?.id,
                contentWarning: warningText.isEmpty ? nil : warningText, sensitive: sensitive,
                visibility: destination == nil ? (visibility?.rawValue ?? (inReplyToId == nil ? "public" : nil)) : nil,
                poll: poll?.request, language: language, roomId: destination?.id)
            NoteLanguages.remember(language)
            if let scheduledAt {
                let scheduled = try await NoteAPI.schedule(draft, at: scheduledAt)
                ScheduledNotesStore.shared.added(scheduled)
                ToastCenter.shared.show(
                    String(localized: "\(scheduled.scheduledAt.formatted(.dateTime.month().day().hour().minute()))에 올릴게요"))
                dismiss()
                return
            }
            let rest = parts.map(\.text).filter { NoteText.length($0) > 0 }
            var created: Note
            if rest.isEmpty {
                created = try await NoteAPI.create(draft)
            } else {
                let thread = try await NoteAPI.createThread([draft] + rest.map {
                    NoteDraft(
                        body: NoteText.plain($0), images: [], quotedPostId: nil, inReplyToId: nil,
                        language: language, roomId: destination?.id)
                })
                guard let first = thread.first else { throw URLError(.badServerResponse) }
                created = first
            }
            if created.linkPreview == nil, let linkCard, linkCard.url == cardUrl {
                created.linkPreview = linkCard
            }
            onDone(created)
            dismiss()
        } catch let tooLarge as NoteImageTooLarge {
            errorMessage = tooLarge.errorDescription
        } catch let APIError.server(_, code, _) where code == "NOTE_REPLY_RESTRICTED" {
            errorMessage = String(localized: "이 노트에는 답글을 달 수 없어요")
        } catch {
            errorMessage = scheduledAt == nil
                ? String(localized: "노트를 올리지 못했어요")
                : NoteScheduleText.failure(error)
        }
    }
}

/// 설정의 노트 연합 토글 — 불러오기 전엔 그리지 않는다(잘못된 상태가 번쩍이지 않게). 빈 Group 에
/// 단 .task 는 붙을 자식이 없어 돌지 않으므로 늘 존재하는 VStack 이 불러오기를 맡는다.
struct FederationSettingRow: View {
    @State private var settings: FederationSettings?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let settings {
                Toggle(isOn: Binding(get: { settings.enabled }, set: { next in Task { await set(next) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("다른 서버에 노트 공유")
                            .typeScale(.body)
                            .foregroundStyle(Palette.ink)
                        Group {
                            if let handle = settings.handle {
                                Text("마스토돈·Misskey에서 \(handle)로 찾아 팔로우할 수 있어요. 끄면 팔로워 서버에 계정을 지우라고 알리고 팔로워 목록을 비워요.")
                            } else {
                                Text("마스토돈·Misskey에서 찾아 팔로우할 수 있어요. 끄면 팔로워 서버에 계정을 지우라고 알리고 팔로워 목록을 비워요.")
                            }
                        }
                        .typeScale(.footnote)
                        .foregroundStyle(Palette.secondary)
                    }
                }
                .tint(GlassTokens.prominentTint)
                .disabled(busy)
                .padding(.vertical, 7)
                .accessibilityIdentifier("settings.federation")
            }
        }
        .task { settings = try? await NoteAPI.federationSettings() }
    }

    private func set(_ enabled: Bool) async {
        guard let previous = settings else { return }
        busy = true
        defer { busy = false }
        settings = FederationSettings(enabled: enabled, noticeSeen: previous.noticeSeen, handle: previous.handle)
        do {
            settings = try await NoteAPI.updateFederationSettings(enabled: enabled)
        } catch {
            settings = previous
            ToastCenter.shared.show(String(localized: "설정을 바꾸지 못했습니다"))
        }
    }
}

private struct NoteLengthRing: View {
    let length: Int
    let limit: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let left = limit - length
        let near = left <= 20
        ZStack {
            Circle().stroke(Palette.hairlineStrong, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(1, CGFloat(length) / CGFloat(max(limit, 1))))
                .stroke(left < 0 ? Palette.danger : Palette.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if near {
                Text(verbatim: "\(left)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(left < 0 ? Palette.danger : Palette.secondary)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: near ? 28 : 22, height: near ? 28 : 22)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: near)
        .accessibilityElement()
        .accessibilityLabel(left < 0 ? Text("\(limit)자까지 쓸 수 있어요") : Text("\(left)자 남음"))
    }
}

enum NoteLinkTarget: Hashable {
    case tag(String)
    case member(String)
}

/// 본문의 #해시태그는 그 태그 화면의 노트 탭으로, @회원은 그 프로필로 — 노트를 그리는 화면
/// 루트에 단다(줄마다 달면 지연 목록 안의 navigationDestination 이 무시된다).
struct NoteTextLinks: ViewModifier {
    var memberTab: AuthorTab = .notes
    @State private var target: NoteLinkTarget?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let found = NoteText.target(from: url) else { return .systemAction }
                target = found
                return .handled
            })
            .navigationDestination(item: $target) { target in
                switch target {
                case let .tag(name): TagFeedView(tag: name, initialTab: .notes)
                case let .member(username): AuthorBlogView(username: username, initialTab: memberTab)
                }
            }
    }
}

extension View {
    func noteTextLinks(memberTab: AuthorTab = .notes) -> some View { modifier(NoteTextLinks(memberTab: memberTab)) }
}

/// 수정 기록 — 마스토돈처럼 판마다 시각과 본문을 위에서부터 최신순으로. 첫째가 지금 판이다.
struct NoteHistorySheet: View {
    let noteId: Int64
    @State private var phase: LoadState<NoteHistory> = .idle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle, .loading:
                    KurlLoadingMark().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ErrorState(message: message, retry: { Task { await load() } })
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                case .loaded(let history):
                    List {
                        ForEach(Array(history.versions.enumerated()), id: \.offset) { index, version in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(index == 0 ? "지금" : "이전")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(index == 0 ? Palette.ink : Palette.secondary)
                                    if let at = version.at {
                                        Text(at, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
                                            .foregroundStyle(Palette.secondary)
                                    }
                                }
                                .typeScale(.meta)
                                if let warning = version.contentWarning {
                                    Text(verbatim: warning)
                                        .typeScale(.note)
                                        .foregroundStyle(Palette.secondary)
                                }
                                Text(version.body)
                                    .typeScale(.note)
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("note.version.\(index)")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("수정 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func load() async {
        phase = .loading
        do {
            phase = .loaded(try await NoteAPI.history(of: noteId))
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
