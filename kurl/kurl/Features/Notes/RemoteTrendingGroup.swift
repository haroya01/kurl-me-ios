import SwiftUI

@Observable
@MainActor
final class TrendingNoteActions {
    enum Outcome: Equatable {
        case done(Note)
        case signIn
        case failed(String)
        case busy
    }

    let item: TrendingNote
    private let signedIn: @MainActor () -> Bool
    private(set) var local: Note?
    private(set) var liked = false
    private(set) var working = false
    private(set) var followed: RemoteAccount?
    private(set) var reposted = false
    private var likedAtResolve = false
    private var repostedAtResolve = false
    private var liking = false
    private var reposting = false
    private var serverLiked: Bool?
    private var serverReposted: Bool?

    var likeCount: Int64 {
        max(item.likeCount + (liked ? 1 : 0) - (likedAtResolve ? 1 : 0), 0)
    }

    var repostCount: Int64 {
        max((item.repostCount ?? 0) + (reposted ? 1 : 0) - (repostedAtResolve ? 1 : 0), 0)
    }

    init(item: TrendingNote, signedIn: @escaping @MainActor () -> Bool = { AuthStore.shared.isSignedIn }) {
        self.item = item
        self.signedIn = signedIn
    }

    func localNote(quietly: Bool = false) async -> Outcome {
        if let local { return .done(local) }
        guard signedIn() else { return .signIn }
        if !quietly { working = true }
        defer { if !quietly { working = false } }
        switch await FederationAPI.resolve(item.uri) {
        case .note(let note):
            local = note
            likedAtResolve = note.likedByMe == true
            repostedAtResolve = note.repostedByMe == true
            serverLiked = likedAtResolve
            serverReposted = repostedAtResolve
            if !liking { liked = likedAtResolve }
            if !reposting { reposted = repostedAtResolve }
            return .done(note)
        case .signIn:
            return .signIn
        case .missing(let domain):
            return .failed(String(localized: "\(domain) 서버에서 찾지 못했어요"))
        case .unreachable(let domain):
            return .failed(String(localized: "\(domain) 서버가 응답하지 않아요"))
        case .account, .hidden:
            return .failed(String(localized: "다른 서버 노트를 가져오지 못했어요"))
        }
    }

    func toggleLike() async -> Outcome {
        guard signedIn() else { return .signIn }
        guard !liking else { return .busy }
        liking = true
        defer { liking = false }
        let target = !liked
        liked = target
        let outcome = await localNote(quietly: true)
        guard case .done(let note) = outcome else {
            liked = !target
            return outcome
        }
        if serverLiked == target { return outcome }
        do {
            liked = try await NoteAPI.setLike(id: note.id, on: target).liked
            serverLiked = liked
            return outcome
        } catch {
            liked = !target
            return .failed(String(localized: "좋아요를 반영하지 못했어요"))
        }
    }

    func toggleRepost() async -> Outcome {
        guard signedIn() else { return .signIn }
        guard !reposting else { return .busy }
        reposting = true
        defer { reposting = false }
        let target = !reposted
        reposted = target
        let outcome = await localNote(quietly: true)
        guard case .done(let note) = outcome else {
            reposted = !target
            return outcome
        }
        if serverReposted == target { return outcome }
        do {
            reposted = try await NoteAPI.setRepost(id: note.id, on: target).reposted
            serverReposted = reposted
            return outcome
        } catch {
            reposted = !target
            return .failed(String(localized: "리포스트하지 못했어요"))
        }
    }

    func followAuthor() async -> Outcome {
        let outcome = await localNote()
        guard case .done(let note) = outcome else { return outcome }
        guard let remoteId = note.author.remoteId else {
            return .failed(String(localized: "다른 서버 노트를 가져오지 못했어요"))
        }
        do {
            followed = try await FederationAPI.setFollowing(true, id: remoteId)
            return outcome
        } catch {
            return .failed(FederationAPI.message(for: error))
        }
    }
}

struct TrendingNoteRow: View {
    let item: TrendingNote
    var showsContext = true
    var marker: Text?
    @State private var actions: TrendingNoteActions
    @State private var replyTarget: Note?
    @State private var quoteTarget: Note?
    @State private var repostTaps = 0
    @State private var replies = 0
    @State private var likeTaps = 0
    @State private var showLogin = false
    @State private var loginMessage: LocalizedStringKey = "다른 서버의 노트를 보려면 로그인하세요"
    @State private var original: LegalLink?
    @Environment(\.openNoteRoute) private var openNoteRoute
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(item: TrendingNote, showsContext: Bool = true, context: Text? = nil) {
        self.item = item
        self.showsContext = showsContext
        self.marker = context
        _actions = State(initialValue: TrendingNoteActions(item: item))
    }

    private var unit: CGFloat { min(scale, 1.8) }
    private static let actionBox: CGFloat = 22

    var body: some View {
        NoteRowView(
            note: item.displayNote, onChange: { _ in }, onDelete: { _ in },
            detached: NoteRowDetached(
                context: context, open: open, openAuthor: openAuthor, reply: reply,
                menu: AnyView(menu), actions: AnyView(actionBar)))
            .sheet(item: $replyTarget) { note in
                NoteComposeSheet(mode: .reply(note)) { posted in
                    replies += 1
                    NoteReplyToast.show(posted, open: openNoteRoute)
                }
            }
            .sheet(item: $quoteTarget) { note in
                NoteComposeSheet(mode: .quote(QuotedNote(note))) { _ in }
            }
            .sheet(item: $original) { SafariView(url: $0.url).ignoresSafeArea() }
            .loginPrompt(isPresented: $showLogin, message: loginMessage)
            .sensoryFeedback(.success, trigger: replies)
            .accessibilityIdentifier("trending.note")
    }

    private var context: Text? {
        if let marker { return marker }
        guard showsContext, let first = item.servers.first else { return nil }
        let others = item.servers.count - 1
        return others > 0 ? Text("\(first) 외 \(others)곳에서 인기") : Text("\(first)에서 인기")
    }

    private var actionBar: some View {
        HStack(spacing: 20) {
            Button {
                likeTaps += 1
                Task { await like() }
            } label: {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .heart, active: actions.liked, size: Self.actionBox * unit)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : actions.liked))
                    if actions.likeCount > 0 {
                        Text("\(actions.likeCount)")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(actions.likeCount)))
                    }
                }
                .typeScale(.lede)
                .foregroundStyle(actions.liked ? Palette.accent : Palette.ink)
                .animation(reduceMotion ? nil : Motion.move, value: actions.likeCount)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
            .accessibilityLabel(Text("좋아요"))
            .accessibilityAddTraits(actions.liked ? [.isSelected] : [])

            Button(action: reply) {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .reply, size: Self.actionBox * unit)
                    if item.replyCount > 0 { Text("\(item.replyCount)").monospacedDigit() }
                }
                .typeScale(.lede)
                .foregroundStyle(Palette.ink)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("답글 쓰기"))
            .accessibilityValue(Text("답글 \(item.replyCount)"))

            Menu {
                Button(role: actions.reposted ? .destructive : nil) {
                    repostTaps += 1
                    Task { await repost() }
                } label: {
                    Label(
                        actions.reposted ? LocalizedStringKey("리포스트 취소") : LocalizedStringKey("리포스트"),
                        systemImage: "arrow.2.squarepath")
                }
                Button(action: quote) {
                    Label("인용", systemImage: "quote.opening")
                }
            } label: {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .repost, active: actions.reposted, size: Self.actionBox * unit)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : actions.reposted))
                    if actions.repostCount > 0 {
                        Text("\(actions.repostCount)")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(actions.repostCount)))
                    }
                }
                .typeScale(.lede)
                .foregroundStyle(actions.reposted ? Palette.accent : Palette.ink)
                .animation(reduceMotion ? nil : Motion.move, value: actions.repostCount)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: repostTaps)
            .accessibilityLabel(Text("리포스트 메뉴"))
            .accessibilityAddTraits(actions.reposted ? [.isSelected] : [])
            .accessibilityIdentifier("trending.repost")

            Spacer(minLength: 0)
            if actions.working {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var menu: some View {
        Menu {
            if let url = item.originalURL {
                Button {
                    original = LegalLink(url: url)
                } label: {
                    Label("원문에서 보기", systemImage: "arrow.up.right")
                }
            }
            Button {
                Task { await follow() }
            } label: {
                Label("팔로우", systemImage: "person.badge.plus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15 * unit, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 32 * unit, height: 22 * unit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("노트 메뉴"))
        .accessibilityIdentifier("trending.menu")
    }

    private func openAuthor() {
        if let route = item.authorRoute {
            openNoteRoute?(route)
            return
        }
        Task {
            guard case .done(let note) = settle(await actions.localNote(), "다른 서버 계정을 보려면 로그인하세요")
            else { return }
            openNoteRoute?(note.author.notesRoute)
        }
    }

    private func open() {
        Task {
            guard case .done(let note) = settle(await actions.localNote(), "다른 서버의 노트를 보려면 로그인하세요")
            else { return }
            openNoteRoute?(.note(id: note.id))
        }
    }

    private func reply() {
        Task {
            guard case .done(let note) = settle(await actions.localNote(), "답글을 달려면 로그인하세요")
            else { return }
            replyTarget = note
        }
    }

    private func repost() async {
        _ = settle(await actions.toggleRepost(), "리포스트하려면 로그인하세요")
    }

    private func quote() {
        Task {
            guard case .done(let note) = settle(await actions.localNote(), "인용하려면 로그인하세요") else { return }
            quoteTarget = note
        }
    }

    private func like() async {
        _ = settle(await actions.toggleLike(), "좋아요를 누르려면 로그인하세요")
    }

    private func follow() async {
        guard case .done = settle(await actions.followAuthor(), "팔로우하려면 로그인하세요"),
              let account = actions.followed
        else { return }
        ToastCenter.shared.show(String(localized: account.following ? "팔로우했어요" : "팔로우를 요청했어요"))
    }

    private func settle(
        _ outcome: TrendingNoteActions.Outcome, _ message: LocalizedStringKey
    ) -> TrendingNoteActions.Outcome {
        switch outcome {
        case .done, .busy: break
        case .signIn:
            loginMessage = message
            showLogin = true
        case .failed(let text):
            ToastCenter.shared.show(text)
        }
        return outcome
    }
}
