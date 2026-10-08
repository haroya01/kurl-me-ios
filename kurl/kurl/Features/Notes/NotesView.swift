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
        guard let context = source.filterContext else { return loaded }
        let store = NoteFilterStore.shared
        return loaded.filter { store.verdict(for: $0, in: context) != .hide }
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
            case .bookmarks, .direct: nil
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
            let feed = try await load(0)
            guard myEpoch == epoch else { return }
            page = 0
            loaded = feed.items
            hasNext = feed.hasNext
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
        if let feed = try? await load(page + 1) {
            guard myEpoch == epoch else { return }
            page += 1
            hasNext = feed.hasNext
            let seen = Set(loaded.map(\.id))
            loaded.append(contentsOf: feed.items.filter { !seen.contains($0.id) })
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

/// 노트 한 행 — 스레드 행 문법(헤어라인 구분). 고치기·지우기는 더보기 메뉴나 길게 눌러서.
struct NoteRowView: View {
    let note: Note
    let onChange: (Note) -> Void
    let onDelete: (Int64) -> Void
    var onQuoted: ((Note) -> Void)? = nil
    var repostedBy: String? = nil
    /// 프로필 노트 탭에서만 "고정됨" 줄을 보인다 — 다른 피드에선 고정이 의미 없다(마스토돈과 같다).
    var showsPin = false
    /// 원글 → 답글을 잇는 스레드 선 — 아바타 아래에서 다음 행 아바타 위까지.
    var threadLineBelow = false
    /// 상세의 본 노트 — 머리 줄 아래로 본문을 전체 폭에 한 단계 크게(스레드·X 문법).
    var focused = false

    @State private var liked: Bool
    @State private var likeCount: Int64?
    @State private var likeTaps = 0
    @State private var reposted: Bool
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
    @State private var revealed = false
    @State private var mediaRevealed = false
    @State private var showingHistory = false
    @State private var filterRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.noteFilterContext) private var filterContext

    init(note: Note, onChange: @escaping (Note) -> Void,
         onDelete: @escaping (Int64) -> Void,
         onQuoted: ((Note) -> Void)? = nil, repostedBy: String? = nil,
         showsPin: Bool = false,
         threadLineBelow: Bool = false, focused: Bool = false) {
        self.note = note
        self.onChange = onChange
        self.onDelete = onDelete
        self.onQuoted = onQuoted
        self.repostedBy = repostedBy
        self.showsPin = showsPin
        self.threadLineBelow = threadLineBelow
        self.focused = focused
        _liked = State(initialValue: note.likedByMe == true)
        _likeCount = State(initialValue: note.likeCount)
        _reposted = State(initialValue: note.repostedByMe == true)
        _repostCount = State(initialValue: note.repostCount)
        _bookmarked = State(initialValue: note.bookmarkedByMe == true)
        _conversationMuted = State(initialValue: note.conversationMuted == true)
    }

    private var isMine: Bool { AuthStore.shared.me?.id == note.author.id }

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
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 15, weight: .medium))
                .accessibilityHidden(true)
            Text("필터됨: \(phrases.joined(separator: ", "))")
                .typeScale(.meta)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("보기") {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { filterRevealed = true }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Palette.ink)
            .accessibilityIdentifier("note.filtered.reveal.\(note.id)")
        }
        .foregroundStyle(Palette.secondary)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note.filtered.\(note.id)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let repostedBy {
                HStack(spacing: 12) {
                    NoteGlyphView(glyph: .repost, size: 14)
                        .frame(width: 36, alignment: .trailing)
                    Text("\(repostedBy)님이 리포스트함")
                        .typeScale(.meta)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.secondary)
                .accessibilityElement(children: .combine)
            } else if showsPin, note.pinned == true {
                HStack(spacing: 12) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 36, alignment: .trailing)
                    Text("고정됨")
                        .typeScale(.meta)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Palette.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("note.pinned.\(note.id)")
            }
            if focused { focusedRow } else { row }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .topLeading) {
            if threadLineBelow {
                Capsule()
                    .fill(Palette.hairlineStrong)
                    .frame(width: 2)
                    .padding(.top, 14 + 36 + 6)
                    .padding(.bottom, -8)
                    .padding(.leading, 17)
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
                Button { editing = true } label: { Label("고치기", systemImage: "pencil") }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("노트 삭제", systemImage: "trash")
                }
            }
            if AuthStore.shared.isSignedIn {
                Button { connecting = true } label: {
                    Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
                }
            }
        }
        .sheet(isPresented: $editing) {
            NoteComposeSheet(mode: .edit(note)) { onChange($0) }
        }
        .sheet(isPresented: $quoting) {
            NoteComposeSheet(mode: .quote(QuotedNote(note))) { created in
                ToastCenter.shared.show(String(localized: "인용 노트를 올렸어요"))
                onQuoted?(created)
            }
        }
        .sheet(isPresented: $connecting) {
            ConnectSheet(targetKind: "노트", targetTitle: note.body, blockType: .note, refId: note.id)
        }
        .fullScreenCover(isPresented: $writingPost) {
            if let shareURL { QuotePostComposer(noteURL: shareURL) }
        }
        .alert("이 노트를 지울까요?", isPresented: $confirmDelete) {
            Button("지우기", role: .destructive) { Task { await delete() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("다른 서버로 퍼진 사본에도 지우라는 요청을 보내요.")
        }
        .loginPrompt(isPresented: $showLoginSheet, message: "노트에 좋아요 남기기")
        .onChange(of: note) { _, next in
            liked = next.likedByMe == true
            likeCount = next.likeCount
            reposted = next.repostedByMe == true
            repostCount = next.repostCount
            bookmarked = next.bookmarkedByMe == true
            conversationMuted = next.conversationMuted == true
        }
    }

    private var avatarLink: some View {
        NavigationLink(value: note.author.notesRoute) {
            AvatarView(author: note.author, size: 36)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private var focusedRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink(value: note.author.notesRoute) {
                    AvatarView(author: note.author, size: 44)
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
                if !note.author.isRemote {
                    FollowButton(username: note.author.username)
                }
                moreMenu
            }
            warningBar
            if !folded {
                if !note.body.isEmpty {
                    Text(NoteText.attributed(note.body, mentions: note.mentions ?? []))
                        .typeScale(.noteFocus)
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.link)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                attachments
            }
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
                                .font(.system(size: 12, weight: .semibold))
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
        HStack(alignment: .top, spacing: 12) {
            avatarLink

            VStack(alignment: .leading, spacing: 2) {
                header
                warningBar
                if !folded, !note.body.isEmpty {
                    NavigationLink(value: Route.note(id: note.id)) {
                        Text(NoteText.attributed(note.body, mentions: note.mentions ?? []))
                            .typeScale(.note)
                            .foregroundStyle(Palette.ink)
                            .tint(Palette.link)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note.body.\(note.id)")
                }
                if !folded { attachments }
                actions(spread: false)
                    .padding(.top, 10)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            NavigationLink(value: note.author.notesRoute) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(note.author.shownName)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .layoutPriority(1)
                    if note.author.hasDisplayName || note.author.isRemote {
                        Text(verbatim: "@\(note.author.username)")
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .typeScale(.note)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            if let date = note.createdAt {
                Text(date.relativeCompact)
                    .typeScale(.note)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            if note.noteVisibility != .public {
                Image(systemName: note.noteVisibility.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .accessibilityLabel(Text(note.noteVisibility.title))
                    .accessibilityIdentifier("note.visibility.\(note.id)")
            }
            if note.editedAt != nil {
                Text("고침")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
            moreMenu
        }
    }

    private var folded: Bool { note.contentWarning != nil && !revealed }

    /// 열람 주의 — 문구만 보이고 본문·사진·카드는 접힌다. 펼치면 사진도 함께 보인다(한 번만 누르게).
    @ViewBuilder private var warningBar: some View {
        if let warning = note.contentWarning {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(warning)
                    .typeScale(focused ? .noteFocus : .note)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(revealed ? "숨기기" : "내용 보기") {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { revealed.toggle() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.ink)
                .accessibilityIdentifier("note.reveal.\(note.id)")
            }
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 6)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radius))
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("note.warning.\(note.id)")
        }
    }

    private var hidesMedia: Bool {
        note.sensitive == true && note.contentWarning == nil && !mediaRevealed && !note.media.isEmpty
    }

    @ViewBuilder private var attachments: some View {
        if let poll = note.poll {
            NotePollView(noteId: note.id, poll: poll) { updated in
                var next = note
                next.poll = updated
                onChange(next)
            }
            .padding(.top, 8)
        }
        NoteImagesView(media: note.media)
            .allowsHitTesting(!hidesMedia)
            .accessibilityHidden(hidesMedia)
            .overlay {
                if hidesMedia {
                    ZStack {
                        Rectangle().fill(.ultraThickMaterial)
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { mediaRevealed = true }
                        } label: {
                            Label("민감한 사진 · 눌러서 보기", systemImage: "eye.slash")
                                .typeScale(.meta)
                                .fontWeight(.semibold)
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("note.sensitive.\(note.id)")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
                    .transition(.opacity)
                }
            }
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
                Button { editing = true } label: { Label("고치기", systemImage: "pencil") }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("노트 삭제", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 32, height: 22)
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
                    NoteGlyphView(glyph: .heart, active: liked, size: Self.actionBox)
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
            NavigationLink(value: Route.note(id: note.id)) {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .reply, size: Self.actionBox)
                    if note.replyCount > 0 { Text("\(note.replyCount)").monospacedDigit() }
                }
                .typeScale(.lede)
                .foregroundStyle(Palette.ink)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("답글 \(note.replyCount)"))
            .accessibilityIdentifier("note.replies.\(note.id)")

            if spread { Spacer(minLength: 0) }
            repostMenu

            if spread {
                Spacer(minLength: 0)
                Button {
                    bookmarkTaps += 1
                    Task { await toggleBookmark() }
                } label: {
                    NoteGlyphView(glyph: .bookmark, active: bookmarked, size: Self.actionBox)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : bookmarked))
                        .foregroundStyle(bookmarked ? Palette.accent : Palette.ink)
                        .expandTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(bookmarked ? "북마크 해제" : "북마크"))
                .accessibilityAddTraits(bookmarked ? [.isSelected] : [])
                .accessibilityIdentifier("note.bookmark.\(note.id)")
            }

            if let shareURL {
                if spread { Spacer(minLength: 0) }
                shareMenu(shareURL)
            }
        }
    }

    private static let actionBox: CGFloat = 22

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
                    if AuthStore.shared.isSignedIn { writingPost = true } else { showLoginSheet = true }
                } label: {
                    Label("블로그 글로 인용", systemImage: "square.and.pencil")
                }
            }
        } label: {
            NoteGlyphView(glyph: .share, size: Self.actionBox)
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
            NoteGlyphView(glyph: .repost, active: false, size: Self.actionBox)
                .foregroundStyle(Palette.faint)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
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
                if AuthStore.shared.isSignedIn { quoting = true } else { showLoginSheet = true }
            } label: {
                Label("인용", systemImage: "quote.opening")
            }
        } label: {
            HStack(spacing: 4) {
                NoteGlyphView(glyph: .repost, active: reposted, size: Self.actionBox)
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
            showLoginSheet = true
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
            showLoginSheet = true
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

    private func toggleLike() async {
        guard AuthStore.shared.isSignedIn else {
            showLoginSheet = true
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
            ToastCenter.shared.show(String(localized: "좋아요를 반영하지 못했습니다"))
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
private struct GlyphPop: ViewModifier {
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
struct QuotedPostCard: View {
    let post: QuotedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(post.authorUsername)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("· 블로그 글")
                    .foregroundStyle(Palette.secondary)
            }
            .typeScale(.meta)
            Text(post.title)
                .typeScale(.note)
                .fontWeight(.medium)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
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

/// 인용된 노트 — 작성자·시간·글(4줄까지)·사진 줄. 사진은 글 아래 작은 정사각형으로.
struct QuotedNoteCard: View {
    let note: QuotedNote
    /// 글에 실린 노트 — 본문을 자르지 않는다.
    var full = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AvatarView(author: note.author, size: 20)
                Text(note.author.username)
                    .typeScale(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let date = note.createdAt {
                    Text(date.relativeCompact)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            if let warning = note.contentWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .typeScale(.note)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
            } else if !note.body.isEmpty {
                Text(note.body)
                    .typeScale(.note)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(full ? nil : 4)
                    .multilineTextAlignment(.leading)
            }
            if note.contentWarning == nil, note.sensitive != true, !note.media.isEmpty {
                HStack(spacing: 6) {
                    ForEach(note.media) { image in
                        RemoteImage(url: URL(string: image.url), maxPixel: 200) { phase in
                            Palette.hairline
                                .overlay {
                                    if case .success(let loaded) = phase {
                                        loaded.resizable().scaledToFill()
                                    }
                                }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusInner))
                        .accessibilityLabel(Text(image.altText ?? String(localized: "사진")))
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
                    .holdsSwipePager()
                }
                ForEach(audio, id: \.url) { item in
                    NoteAudioRow(media: item)
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
        if item.isVideo {
            NoteVideoTile(media: item, height: height) { opened = item }
        } else {
            NoteImageTile(image: item, height: height) { opened = item }
        }
    }
}

private struct NoteImageTile: View {
    let image: NoteMedia
    /// nil = 한 장 — 칼럼 폭에 원래 비율로 맞추고 430pt 를 넘지 않는다.
    let height: CGFloat?
    let onOpen: () -> Void
    @State private var showAlt = false
    /// 비율은 타일을 만들 때 한 번 정하고 바꾸지 않는다. 지연 스택에서 보이는 행의 높이가 이미지 로드로
    /// 바뀌면 SwiftUI 레이아웃이 끝나지 않아 메인 스레드가 멈췄다.
    @State private var ratio: CGFloat

    private static let maxPixel: CGFloat = 900
    private static let unknownRatio: CGFloat = 4.0 / 3.0
    private var url: URL? { URL(string: image.url) }

    init(image: NoteMedia, height: CGFloat?, onOpen: @escaping () -> Void) {
        self.image = image
        self.height = height
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
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius).stroke(Palette.hairline, lineWidth: 0.5))
            .overlay(alignment: .bottomLeading) { altLayer }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
            .onTapGesture(perform: onOpen)
            .accessibilityElement()
            .accessibilityAddTraits([.isImage, .isButton])
            .accessibilityLabel(Text(image.altText ?? String(localized: "사진")))
            .accessibilityHint(Text("두 번 탭하면 크게 봅니다"))
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
                .aspectRatio(ratio, contentMode: .fit)
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

/// 노트 상세 — 원글(답글이면) · 노트 · 답글. 답글은 툴바 버튼이 여는 작성 시트로.
struct NoteDetailView: View {
    let noteId: Int64
    @State private var thread: NoteThread?
    @State private var failed: String?
    @State private var replying = false
    @State private var deleted = false
    @State private var showLoginSheet = false
    @State private var replied = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let thread {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let parent = thread.parent {
                            NoteRowView(
                                note: parent, onChange: { _ in }, onDelete: { _ in }, threadLineBelow: true)
                        }
                        NoteRowView(
                            note: thread.note,
                            onChange: { note in self.thread = NoteThread(note: note, parent: thread.parent, replies: thread.replies) },
                            onDelete: { _ in dismiss() },
                            focused: true)
                        Hairline().padding(.horizontal, -Metrics.noteGutter)
                        HStack(spacing: 6) {
                            Text("답글")
                                .fontWeight(.semibold)
                                .foregroundStyle(Palette.ink)
                            if !thread.replies.isEmpty {
                                Text(verbatim: "\(thread.replies.count)")
                                    .foregroundStyle(Palette.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .typeScale(.note)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                        if thread.replies.isEmpty {
                            Text("아직 답글이 없어요")
                                .typeScale(.note)
                                .foregroundStyle(Palette.secondary)
                                .padding(.vertical, 14)
                        }
                        let replies = thread.replies.filter {
                            NoteFilterStore.shared.verdict(for: $0, in: .thread) != .hide
                        }
                        ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                            NoteRowView(
                                note: reply,
                                onChange: { next in update { $0.replies = $0.replies.map { $0.id == next.id ? next : $0 } } },
                                onDelete: { id in update { $0.replies.removeAll { $0.id == id } } })
                                .environment(\.noteFilterContext, .thread)
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
                .brandRefreshable { await load() }
            } else if let failed {
                ErrorState(message: failed, retry: { Task { await load() } })
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
            if let thread { replyBar(to: thread.note.author.username) }
        }
        .sheet(isPresented: $replying) {
            NoteComposeSheet(mode: .new(quote: nil, inReplyToId: noteId)) { reply in
                update {
                    $0.replies.append(reply)
                }
                replied += 1
            }
        }
        .sensoryFeedback(.success, trigger: replied)
        .loginPrompt(isPresented: $showLoginSheet, message: "답글 남기기")
        .task { if thread == nil { await load() } }
    }

    /// 스레드처럼 아래에 늘 있는 답글 입구 — 누르면 답글 시트.
    private func replyBar(to username: String) -> some View {
        Button {
            if AuthStore.shared.isSignedIn { replying = true } else { showLoginSheet = true }
        } label: {
            ReplyPrompt(text: Text("\(username)님에게 답글 남기기"))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("답글 달기"))
        .accessibilityIdentifier("note.reply")
        .padding(.horizontal, Metrics.noteGutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: Metrics.readingColumn)
        .frame(maxWidth: .infinity)
        .background(Palette.readingBg)
        .overlay(alignment: .top) { Hairline() }
    }

    private struct MutableThread {
        var note: Note
        var parent: Note?
        var replies: [Note]
    }

    private func update(_ change: (inout MutableThread) -> Void) {
        guard let thread else { return }
        var mutable = MutableThread(note: thread.note, parent: thread.parent, replies: thread.replies)
        change(&mutable)
        self.thread = NoteThread(note: mutable.note, parent: mutable.parent, replies: mutable.replies)
    }

    private func load() async {
        do {
            thread = try await NoteAPI.thread(id: noteId)
            failed = nil
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
        case quote(QuotedNote)
        case edit(Note)
    }

    private struct PickedImage: Identifiable {
        let id = UUID()
        let image: UIImage
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
    let onDone: (Note) -> Void

    @State private var text: String
    @State private var warning: String
    @State private var warns: Bool
    @State private var sensitive: Bool
    /// nil = 답글이면 원글과 같은 범위(서버가 이어받는다), 아니면 공개.
    @State private var visibility: NoteVisibility?
    @State private var quote: QuotedPost?
    @State private var picked: [PickedImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
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
    @FocusState private var focused: Bool
    @FocusState private var focusedPart: UUID?
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, onDone: @escaping (Note) -> Void) {
        self.mode = mode
        self.onDone = onDone
        switch mode {
        case let .new(quote, _):
            _text = State(initialValue: "")
            _quote = State(initialValue: quote)
        case .quote:
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
    private var inReplyToId: Int64? { if case let .new(_, id) = mode { id } else { nil } }
    private var quotedNote: QuotedNote? { if case let .quote(note) = mode { note } else { nil } }
    private var length: Int { NoteText.length(text) }
    private var cardUrl: String? {
        isEdit
            ? nil
            : NoteText.previewUrl(
                text, hasMedia: !picked.isEmpty || poll != nil, hasQuote: quote != nil || quotedNote != nil)
    }
    private var placeholder: LocalizedStringKey {
        if quotedNote != nil { return "생각을 덧붙여 보세요" }
        return inReplyToId == nil ? "지금 떠오른 생각을 짧게 남겨 보세요" : "답글을 남겨 보세요"
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
        !isEdit && scheduledAt == nil && parts.count < NoteAPI.maxThreadNotes - 1
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
                                    TextField("열람 주의 문구 (예: 스포일러)", text: $warning, axis: .vertical)
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
                                    Image(systemName: warns ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                        .font(.system(size: 17))
                                        .foregroundStyle(warns ? Palette.ink : Palette.secondary)
                                        .frame(width: 32, height: 28, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(warns ? "열람 주의 끄기" : "열람 주의")
                                .accessibilityIdentifier("noteCompose.warningToggle")
                                if hasImages, !warns {
                                    Button {
                                        sensitive.toggle()
                                    } label: {
                                        Image(systemName: sensitive ? "eye.slash.fill" : "eye.slash")
                                            .font(.system(size: 17))
                                            .foregroundStyle(sensitive ? Palette.ink : Palette.secondary)
                                            .frame(width: 32, height: 28, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(sensitive ? "민감한 사진 표시 끄기" : "민감한 사진으로 표시")
                                    .accessibilityIdentifier("noteCompose.sensitiveToggle")
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
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.readingBg)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if hasDraft { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if posting {
                            ProgressView()
                        } else {
                            Text(
                                isEdit
                                    ? LocalizedStringKey("저장")
                                    : scheduledAt == nil ? LocalizedStringKey("올리기") : LocalizedStringKey("예약"))
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
            .onAppear { focused = true }
            .task(id: cardUrl) { await loadLinkCard() }
        }
        .interactiveDismissDisabled(posting || hasDraft)
    }

    private var shownVisibility: NoteVisibility { visibility ?? .public }

    @ViewBuilder private var visibilityLabel: some View {
        HStack(spacing: 6) {
            if visibility == nil, inReplyToId != nil {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 13, weight: .medium))
                Text("원글과 같은 범위")
                    .typeScale(.meta)
            } else {
                Image(systemName: shownVisibility.symbol)
                    .font(.system(size: 13, weight: .medium))
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
            if isEdit {
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
                if parts.isEmpty {
                    Button {
                        pickingSchedule = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: scheduledAt == nil ? "clock" : "clock.fill")
                            if let scheduledAt {
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
        .background(Palette.readingBg)
        .overlay(alignment: .top) { Hairline() }
    }

    @ViewBuilder private func myAvatar(size: CGFloat) -> some View {
        if let me = AuthStore.shared.me {
            AvatarView(
                author: Author(id: me.id ?? 0, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl),
                size: size)
        }
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
                TextField("이어서 써 보세요", text: part.text, axis: .vertical)
                    .typeScale(.note)
                    .lineLimit(1...20)
                    .focused($focusedPart, equals: id)
                    .accessibilityIdentifier("noteCompose.part")
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
                                    if !item.altText.isEmpty {
                                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                    }
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
            guard picked.count < NoteAPI.maxImages,
                  let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }
            picked.append(PickedImage(image: image))
        }
        pickerItems = []
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
                guard let jpeg = item.image.jpegData(compressionQuality: 0.85) else { continue }
                let key = try await NoteAPI.uploadImage(jpegData: jpeg)
                images.append(NoteDraft.Image(
                    key: key, altText: item.altText,
                    width: Int((item.image.size.width * item.image.scale).rounded()),
                    height: Int((item.image.size.height * item.image.scale).rounded())))
            }
            let draft = NoteDraft(
                body: NoteText.plain(text), images: images, quotedPostId: quote?.id, inReplyToId: inReplyToId,
                quotedNoteId: quotedNote?.id,
                contentWarning: warningText.isEmpty ? nil : warningText, sensitive: sensitive,
                visibility: visibility?.rawValue ?? (inReplyToId == nil ? "public" : nil),
                poll: poll?.request, language: language)
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
                    NoteDraft(body: NoteText.plain($0), images: [], quotedPostId: nil, inReplyToId: nil, language: language)
                })
                guard let first = thread.first else { throw URLError(.badServerResponse) }
                created = first
            }
            if created.linkPreview == nil, let linkCard, linkCard.url == cardUrl {
                created.linkPreview = linkCard
            }
            onDone(created)
            dismiss()
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
                .stroke(left < 0 ? Palette.danger : Palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
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
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .typeScale(.meta)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Palette.ink)
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
                ToolbarItem(placement: .confirmationAction) {
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
