import SwiftUI

struct NoteViewerActions: View {
    let note: Note
    let engagement: NoteEngagement
    let shareURL: URL?
    let onReplied: (Note) -> Void
    var onQuoted: ((Note) -> Void)?

    @State private var replying = false
    @State private var quoting = false
    @State private var showLogin = false
    @State private var loginMessage: LocalizedStringKey = "좋아요를 누르려면 로그인하세요"
    @State private var likeTaps = 0
    @State private var repostTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private static let glyphBox: CGFloat = 20
    private static let dimmed = Color.white.opacity(0.4)

    private var unit: CGFloat { min(scale, 1.8) }
    private var access: NoteReplyAccess { NoteReplyAccess(note, signedIn: AuthStore.shared.isSignedIn) }

    var body: some View {
        HStack(spacing: 0) {
            likeButton
            Spacer(minLength: 0)
            replyButton
            if note.room == nil {
                Spacer(minLength: 0)
                repostControl
                if let shareURL {
                    Spacer(minLength: 0)
                    shareButton(shareURL)
                }
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $replying) {
            NoteComposeSheet(mode: .reply(note)) { onReplied($0) }
        }
        .sheet(isPresented: $quoting) {
            NoteComposeSheet(mode: .quote(QuotedNote(note))) { created in
                ToastCenter.shared.show(String(localized: "인용 노트를 올렸어요"))
                onQuoted?(created)
            }
        }
        .loginPrompt(isPresented: $showLogin, message: loginMessage)
    }

    private var likeButton: some View {
        Button {
            likeTaps += 1
            Task { settle(await engagement.toggleLike(), signIn: "좋아요를 누르려면 로그인하세요") }
        } label: {
            HStack(spacing: 4) {
                NoteGlyphView(glyph: .heart, active: engagement.liked, size: Self.glyphBox * unit)
                    .modifier(GlyphPop(trigger: reduceMotion ? false : engagement.liked))
                if let likeCount = engagement.likeCount, likeCount > 0 {
                    Text("\(likeCount)")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(likeCount)))
                }
            }
            .typeScale(.lede)
            .foregroundStyle(engagement.liked ? Palette.accent : .white)
            .expandTapTarget()
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
        .accessibilityLabel(Text("좋아요"))
        .accessibilityAddTraits(engagement.liked ? [.isSelected] : [])
        .accessibilityIdentifier("viewer.like")
    }

    private var replyButton: some View {
        let access = access
        return Button(action: startReply) {
            HStack(spacing: 4) {
                NoteGlyphView(glyph: .reply, size: Self.glyphBox * unit)
                if note.replyCount > 0 { Text("\(note.replyCount)").monospacedDigit() }
            }
            .typeScale(.lede)
            .foregroundStyle(access.isClosed ? Self.dimmed : .white)
            .expandTapTarget()
        }
        .buttonStyle(.plain)
        .disabled(access.isClosed)
        .accessibilityLabel(Text("답글 쓰기"))
        .accessibilityValue(Text("답글 \(note.replyCount)"))
        .accessibilityHint(access.notice.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityIdentifier("viewer.reply")
    }

    @ViewBuilder private var repostControl: some View {
        if note.noteVisibility.shareable {
            Menu {
                Button(role: engagement.reposted ? .destructive : nil) {
                    repostTaps += 1
                    Task { settle(await engagement.toggleRepost(), signIn: "리포스트하려면 로그인하세요") }
                } label: {
                    Label(
                        engagement.reposted ? LocalizedStringKey("리포스트 취소") : LocalizedStringKey("리포스트"),
                        systemImage: "arrow.2.squarepath")
                }
                Button {
                    if AuthStore.shared.isSignedIn { quoting = true } else { askLogin("인용하려면 로그인하세요") }
                } label: {
                    Label("인용", systemImage: "quote.opening")
                }
            } label: {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .repost, active: engagement.reposted, size: Self.glyphBox * unit)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : engagement.reposted))
                    if let repostCount = engagement.repostCount, repostCount > 0 {
                        Text("\(repostCount)")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(repostCount)))
                    }
                }
                .typeScale(.lede)
                .foregroundStyle(engagement.reposted ? Palette.accent : .white)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: repostTaps)
            .accessibilityLabel(Text("리포스트 메뉴"))
            .accessibilityAddTraits(engagement.reposted ? [.isSelected] : [])
            .accessibilityIdentifier("viewer.repost")
        } else {
            NoteGlyphView(glyph: .repost, active: false, size: Self.glyphBox * unit)
                .foregroundStyle(Self.dimmed)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8 * unit, weight: .bold))
                        .foregroundStyle(Self.dimmed)
                }
                .expandTapTarget()
                .accessibilityLabel(Text("리포스트할 수 없는 노트"))
                .accessibilityIdentifier("viewer.repost")
        }
    }

    private func shareButton(_ url: URL) -> some View {
        ShareLink(item: url) {
            NoteGlyphView(glyph: .share, size: Self.glyphBox * unit)
                .foregroundStyle(.white)
                .expandTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("공유"))
        .accessibilityIdentifier("viewer.share")
    }

    private func startReply() {
        switch access {
        case .open: replying = true
        case .needsSignIn: askLogin("답글을 달려면 로그인하세요")
        case .closed: break
        }
    }

    private func askLogin(_ message: LocalizedStringKey) {
        loginMessage = message
        showLogin = true
    }

    private func settle(_ outcome: NoteEngagement.Outcome, signIn message: LocalizedStringKey) {
        switch outcome {
        case .done: break
        case .signIn: askLogin(message)
        case .failed(let text): ToastCenter.shared.show(text)
        }
    }
}
