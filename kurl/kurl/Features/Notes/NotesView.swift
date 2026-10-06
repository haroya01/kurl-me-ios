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
    private(set) var items: [Note] = []
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var isLoadingMore = false

    private var page = 0
    private var hasNext = true
    private var epoch = 0
    private let source: Source

    enum Source {
        case everyone
        case author(String)
        case reposts(String)
    }

    init(author: String? = nil) {
        source = author.map(Source.author) ?? .everyone
    }

    init(repostsBy username: String) {
        source = .reposts(username)
    }

    private func load(_ page: Int) async throws -> NoteFeed {
        switch source {
        case .everyone: try await NoteAPI.everyone(page: page)
        case let .author(username): try await NoteAPI.byAuthor(username, page: page)
        case let .reposts(username): try await NoteAPI.reposts(username, page: page)
        }
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty { phase = .loading }
        do {
            let feed = try await load(0)
            guard myEpoch == epoch else { return }
            page = 0
            items = feed.items
            hasNext = feed.hasNext
            phase = .loaded(true)
        } catch {
            guard myEpoch == epoch else { return }
            if items.isEmpty {
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
            let seen = Set(items.map(\.id))
            items.append(contentsOf: feed.items.filter { !seen.contains($0.id) })
        }
    }

    func inserted(_ note: Note) {
        withAnimation(.snappy(duration: 0.3)) {
            phase = .loaded(true)
            items.insert(note, at: 0)
        }
    }

    func replaced(_ note: Note) {
        if let index = items.firstIndex(where: { $0.id == note.id }) { items[index] = note }
    }

    func removed(_ id: Int64) {
        _ = withAnimation(.snappy(duration: 0.25)) { items.removeAll { $0.id == id } }
    }
}

/// 노트 한 행 — 스레드 행 문법(헤어라인 구분). 고치기·지우기는 더보기 메뉴나 길게 눌러서.
struct NoteRowView: View {
    let note: Note
    let onChange: (Note) -> Void
    let onDelete: (Int64) -> Void
    var onQuoted: ((Note) -> Void)? = nil
    var repostedBy: String? = nil
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
    @State private var quoting = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var connecting = false
    @State private var showLoginSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(note: Note, onChange: @escaping (Note) -> Void,
         onDelete: @escaping (Int64) -> Void,
         onQuoted: ((Note) -> Void)? = nil, repostedBy: String? = nil,
         threadLineBelow: Bool = false, focused: Bool = false) {
        self.note = note
        self.onChange = onChange
        self.onDelete = onDelete
        self.onQuoted = onQuoted
        self.repostedBy = repostedBy
        self.threadLineBelow = threadLineBelow
        self.focused = focused
        _liked = State(initialValue: note.likedByMe == true)
        _likeCount = State(initialValue: note.likeCount)
        _reposted = State(initialValue: note.repostedByMe == true)
        _repostCount = State(initialValue: note.repostCount)
    }

    private var isMine: Bool { AuthStore.shared.me?.id == note.author.id }

    var body: some View {
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
        }
    }

    private var avatarLink: some View {
        NavigationLink(value: Route.authorNotes(username: note.author.username)) {
            AvatarView(author: note.author, size: 36)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private var focusedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                avatarLink
                header
            }
            if !note.body.isEmpty {
                Text(NoteText.attributed(note.body))
                    .typeScale(.noteFocus)
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.link)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            attachments
            footer
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarLink

            VStack(alignment: .leading, spacing: 2) {
                header
                if !note.body.isEmpty {
                    Text(NoteText.attributed(note.body))
                        .typeScale(.note)
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.link)
                        .fixedSize(horizontal: false, vertical: true)
                }
                attachments
                footer
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            NavigationLink(value: Route.authorNotes(username: note.author.username)) {
                Text(note.author.username)
                    .typeScale(.note)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            if let date = note.createdAt {
                Text(date.relativeCompact)
                    .typeScale(.note)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
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

    @ViewBuilder private var attachments: some View {
        NoteImagesView(media: note.media)
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
                Button { connecting = true } label: {
                    Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
                }
            }
            if isMine {
                Divider()
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
    }

    private var footer: some View {
        HStack(spacing: 20) {
            Button {
                likeTaps += 1
                Task { await toggleLike() }
            } label: {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .heart, active: liked, size: Self.actionBox)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : liked))
                    if isMine, let likeCount, likeCount > 0 {
                        Text("\(likeCount)").monospacedDigit()
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

            repostMenu

            if let shareURL {
                ShareLink(item: shareURL) {
                    NoteGlyphView(glyph: .share, size: Self.actionBox)
                        .foregroundStyle(Palette.ink)
                        .expandTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("공유"))
                .accessibilityIdentifier("note.share.\(note.id)")
            }
        }
        .padding(.top, 10)
    }

    private static let actionBox: CGFloat = 22

    private var repostMenu: some View {
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
                if isMine, let repostCount, repostCount > 0 {
                    Text("\(repostCount)").monospacedDigit()
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
        reposted = target
        if let count = repostCount { repostCount = count + (target ? 1 : -1) }
        do {
            let status = try await NoteAPI.setRepost(id: note.id, on: target)
            if isMine { repostCount = status.repostCount }
        } catch {
            reposted = !target
            repostCount = previous
            ToastCenter.shared.show(String(localized: "리포스트하지 못했어요"))
        }
    }

    private func toggleLike() async {
        guard AuthStore.shared.isSignedIn else {
            showLoginSheet = true
            return
        }
        let target = !liked
        let previous = likeCount
        liked = target
        if let count = likeCount { likeCount = count + (target ? 1 : -1) }
        do {
            let status = try await NoteAPI.setLike(id: note.id, on: target)
            if isMine { likeCount = status.likeCount }
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
            RoundedRectangle(cornerRadius: Metrics.radiusMini)
                .stroke(Palette.hairlineStrong, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusMini))
    }
}

/// 인용된 노트 — 작성자·시간·글(4줄까지)·사진 줄. 사진은 글 아래 작은 정사각형으로.
struct QuotedNoteCard: View {
    let note: QuotedNote

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
            if !note.body.isEmpty {
                Text(note.body)
                    .typeScale(.note)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            if !note.media.isEmpty {
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
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
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
            RoundedRectangle(cornerRadius: Metrics.radiusMini)
                .stroke(Palette.hairlineStrong, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusMini))
    }
}

extension QuotedNote {
    init(_ note: Note) {
        self.init(id: note.id, body: note.body, createdAt: note.createdAt, author: note.author, media: note.media)
    }
}

/// 사진 1장은 원래 비율(최대 430pt), 여러 장은 같은 높이로 가로로 넘긴다(스레드 문법). 넘기는 줄은
/// 칼럼 밖 화면 끝까지 그려진다. 대체 텍스트가 곧 접근성 라벨이고, 있으면 ALT 배지로도 드러낸다.
private struct NoteImagesView: View {
    let media: [NoteMedia]
    @State private var opened: NoteMedia?

    var body: some View {
        if !media.isEmpty {
            Group {
                if media.count == 1, let image = media.first {
                    NoteImageTile(image: image, height: nil) { opened = image }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(media, id: \.url) { image in
                                NoteImageTile(image: image, height: 240) { opened = image }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.top, 6)
            .fullScreenCover(item: $opened) { image in
                if let url = URL(string: image.url) {
                    ImageLightbox(url: url, caption: image.altText)
                }
            }
        }
    }
}

private struct NoteImageTile: View {
    let image: NoteMedia
    /// nil = 한 장 — 칼럼 폭에 원래 비율로 맞추고 430pt 를 넘지 않는다.
    let height: CGFloat?
    let onOpen: () -> Void
    @State private var showAlt = false

    private static let maxPixel: CGFloat = 900
    private var url: URL? { URL(string: image.url) }

    var body: some View {
        RemoteImage(url: url, maxPixel: Self.maxPixel) { phase in
            Palette.hairline
                .modifier(TileFrame(ratio: aspect(phase), height: height))
                .overlay {
                    if case .success(let loaded) = phase {
                        loaded.resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radiusThumb).stroke(Palette.hairline, lineWidth: 0.5))
            .overlay(alignment: .bottomLeading) { altLayer }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
            .onTapGesture(perform: onOpen)
            .accessibilityElement()
            .accessibilityAddTraits([.isImage, .isButton])
            .accessibilityLabel(Text(image.altText ?? String(localized: "사진")))
            .accessibilityHint(Text("두 번 탭하면 크게 봅니다"))
        }
    }

    private func aspect(_ phase: RemoteImagePhase) -> CGFloat {
        guard case .success = phase, let url,
            let size = RemoteImageCache.shared.cached(url, maxPixel: Self.maxPixel)?.size,
            size.height > 0
        else { return 0.75 }
        return min(max(size.width / size.height, 0.5), 2)
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
                        .background(.black.opacity(0.7), in: Capsule())
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
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
        }
    }
}

private struct TileFrame: ViewModifier {
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

/// 본문 안의 http(s) 주소만 링크로 — 웹·서버와 같은 규칙(끝 문장부호는 링크에서 뺀다).
enum NoteText {
    private static let urlPattern = try? NSRegularExpression(pattern: "https?://[^\\s<]+")
    private static let trailing = CharacterSet(charactersIn: ".,!?:;)]'\"")

    static func attributed(_ body: String) -> AttributedString {
        var result = AttributedString()
        let ns = body as NSString
        var last = 0
        for match in urlPattern?.matches(in: body, range: NSRange(location: 0, length: ns.length)) ?? [] {
            var link = ns.substring(with: match.range)
            while let scalar = link.unicodeScalars.last, trailing.contains(scalar) {
                link.removeLast()
            }
            if match.range.location > last {
                result += AttributedString(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            }
            var part = AttributedString(link)
            part.link = URL(string: link)
            result += part
            last = match.range.location + (link as NSString).length
        }
        if last < ns.length { result += AttributedString(ns.substring(from: last)) }
        return result
    }

    static func length(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
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
                        ForEach(Array(thread.replies.enumerated()), id: \.element.id) { index, reply in
                            NoteRowView(
                                note: reply,
                                onChange: { next in update { $0.replies = $0.replies.map { $0.id == next.id ? next : $0 } } },
                                onDelete: { id in update { $0.replies.removeAll { $0.id == id } } })
                            if index < thread.replies.count - 1 {
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
        .navigationBarTitleDisplayMode(.inline)
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
            HStack(spacing: 10) {
                if let me = AuthStore.shared.me, AuthStore.shared.isSignedIn {
                    AvatarView(
                        author: Author(id: me.id ?? 0, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl),
                        size: 28)
                }
                Text("\(username)님에게 답글 남기기")
                    .typeScale(.note)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.chipBg, in: Capsule())
            .contentShape(Capsule())
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

    let mode: Mode
    let onDone: (Note) -> Void

    @State private var text: String
    @State private var quote: QuotedPost?
    @State private var picked: [PickedImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var posting = false
    @State private var showNotice = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    @State private var altTarget: AltTarget?
    @FocusState private var focused: Bool
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
    }

    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var inReplyToId: Int64? { if case let .new(_, id) = mode { id } else { nil } }
    private var quotedNote: QuotedNote? { if case let .quote(note) = mode { note } else { nil } }
    private var length: Int { NoteText.length(text) }
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
    private var canPost: Bool {
        !posting && length <= NoteAPI.maxLength && (length > 0 || hasImages)
    }
    private var discardTitle: LocalizedStringKey {
        isEdit ? "고친 내용을 버릴까요?" : "작성 중인 노트를 버릴까요?"
    }
    private var hasDraft: Bool {
        if case let .edit(note) = mode { return text != note.body }
        return length > 0 || !picked.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    if let me = AuthStore.shared.me {
                        AvatarView(
                            author: Author(id: me.id ?? 0, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl),
                            size: 36)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = AuthStore.shared.me?.username {
                                Text(name)
                                    .typeScale(.note)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Palette.ink)
                            }
                            TextField(placeholder, text: $text, axis: .vertical)
                                .typeScale(.note)
                                .lineLimit(1...20)
                                .focused($focused)
                                .accessibilityIdentifier("noteCompose.text")
                        }
                        if !picked.isEmpty { pickedStrip }
                        if let quote { quoteCard(quote) }
                        if let quotedNote { QuotedNoteCard(note: quotedNote) }
                        if let errorMessage {
                            Text(errorMessage)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.danger)
                                .fontWeight(.semibold)
                        }
                        if !isEdit {
                            PhotosPicker(
                                selection: $pickerItems,
                                maxSelectionCount: max(0, NoteAPI.maxImages - picked.count),
                                matching: .images
                            ) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(picked.count >= NoteAPI.maxImages ? Palette.faint : Palette.secondary)
                                    .frame(width: 32, height: 28, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .disabled(picked.count >= NoteAPI.maxImages)
                            .accessibilityLabel("사진 추가")
                        }
                    }
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
                            Text(isEdit ? LocalizedStringKey("저장") : LocalizedStringKey("올리기"))
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
        }
        .interactiveDismissDisabled(posting || hasDraft)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .medium))
            Text("누구나 볼 수 있어요")
                .typeScale(.meta)
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

    private var pickedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(picked) { item in
                    let ratio = min(max(item.image.size.width / max(item.image.size.height, 1), 0.5), 1.8)
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 190 * ratio, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
                        .accessibilityLabel(Text(item.altText.isEmpty ? String(localized: "사진") : item.altText))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { picked.removeAll { $0.id == item.id } }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(.black.opacity(0.6), in: Circle())
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
                                .background(.black.opacity(0.6), in: Capsule())
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
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
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
                onDone(try await NoteAPI.edit(id: note.id, body: text))
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
                images.append(NoteDraft.Image(key: key, altText: item.altText))
            }
            let note = try await NoteAPI.create(
                NoteDraft(
                    body: text, images: images, quotedPostId: quote?.id, inReplyToId: inReplyToId,
                    quotedNoteId: quotedNote?.id))
            onDone(note)
            dismiss()
        } catch {
            errorMessage = String(localized: "노트를 올리지 못했어요")
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
