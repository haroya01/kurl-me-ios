//
//  Conversation.swift
//  kurl
//

import SwiftUI

/// 웹 ConversationName 과 같은 규칙 — 표시 이름이 없으면 @아이디만, 좁으면 아이디가 먼저 잘린다.
struct ConversationName: View {
    let author: Author?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let author, author.hasDisplayName {
                Text(verbatim: author.displayName ?? "")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .layoutPriority(1)
                Text(verbatim: "@\(author.username)")
                    .foregroundStyle(Palette.secondary)
            } else {
                Text(verbatim: "@\(author?.username ?? "?")")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
        }
        .lineLimit(1)
    }

    static func spoken(_ author: Author?) -> String {
        guard let author else { return "?" }
        return author.hasDisplayName ? (author.displayName ?? author.username) : author.username
    }

    @MainActor
    static func spokenLine(
        _ author: Author?, badge: String? = nil, date: Date?, body: String, likes: Int64 = 0
    ) -> String {
        var parts = [spoken(author)]
        if let badge { parts.append(badge) }
        if let date { parts.append(date.relativeCompact) }
        parts.append(body)
        if likes > 0 { parts.append(String(localized: "좋아요 \(likes)")) }
        return parts.joined(separator: ", ")
    }
}

struct ConversationBody: View {
    let text: String
    var mentions: [String] = []

    var body: some View {
        Text(NoteText.attributed(text, mentions: mentions, tags: false))
            .typeScale(.body)
            .foregroundStyle(Palette.body)
            .tint(Palette.link)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

struct ConversationAvatar: View {
    let author: Author?
    var nested = false

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var size: CGFloat { (nested ? 28 : 36) * min(scale, 1.8) }

    var body: some View {
        if let author {
            AvatarView(author: author, size: size)
        } else {
            Circle().fill(Palette.chipBg).frame(width: size, height: size)
        }
    }
}

struct ConversationRow<Content: View, Actions: View, Trailing: View, SpokenActions: View>: View {
    let author: Author?
    let date: Date?
    var nested = false
    var route: Route?
    var badge: LocalizedStringKey?
    let spoken: String
    let identifier: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let spokenActions: () -> SpokenActions

    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    private var destination: Route? {
        if let route { return route }
        return author.map { Route.author(username: $0.username) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarLink
            VStack(alignment: .leading, spacing: 0) {
                header
                content()
                    .padding(.top, 3)
                if Actions.self != EmptyView.self {
                    HStack(spacing: 18) { actions() }
                        .padding(.top, 6)
                }
            }
            .conversationGrouping(label: spoken, identifier: identifier, actions: spokenActions)
        }
    }

    @ViewBuilder private var avatarLink: some View {
        if let destination {
            NavigationLink(value: destination) {
                ConversationAvatar(author: author, nested: nested)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(ConversationName.spoken(author))님 프로필"))
        } else {
            ConversationAvatar(author: author, nested: nested)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let destination {
                NavigationLink(value: destination) {
                    ConversationName(author: author)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ConversationName(author: author)
            }
            if let date {
                Text(verbatim: "·")
                    .foregroundStyle(Palette.faint)
                    .accessibilityHidden(true)
                Text(date.relativeCompact)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize()
            }
            if let badge {
                Text(badge)
                    .font(.system(size: 10 * metaUnit, weight: .semibold))
                    .foregroundStyle(Palette.link)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.chipBg, in: Capsule())
            }
            Spacer(minLength: 0)
            trailing()
        }
        .typeScale(.note)
    }
}

struct ConversationTombstone: View {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Palette.chipBg)
                .frame(width: 36 * min(scale, 1.8), height: 36 * min(scale, 1.8))
                .accessibilityHidden(true)
            Text("삭제된 댓글이에요")
                .typeScale(.note)
                .foregroundStyle(Palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConversationLikeButton: View {
    let liked: Bool
    let count: Int64
    let action: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 13 * metaUnit))
                    .symbolEffect(.bounce, value: reduceMotion ? false : liked)
                if count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .typeScale(.meta)
            .foregroundStyle(liked ? Palette.link : Palette.secondary)
            .expandTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("좋아요"))
        .accessibilityValue(count > 0 ? Text("\(count)") : Text(""))
        .accessibilityAddTraits(liked ? [.isSelected] : [])
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: liked)
    }
}

struct ConversationReplyButton: View {
    let action: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12 * metaUnit, weight: .medium))
                Text("답글")
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.secondary)
            .expandTapTarget()
        }
        .buttonStyle(.plain)
    }
}

struct ConversationIcon: View {
    let systemName: String

    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13 * metaUnit, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .expandTapTarget()
    }
}

extension View {
    /// VoiceOver 가 켜졌을 때만 묶는다 — Voice Control·Switch Control 은 안쪽 버튼을 하나씩 겨눠야 한다.
    /// `--a11y-group` 은 묶기를 강제한다.
    func conversationGrouping<A: View>(
        label: String, identifier: String, @ViewBuilder actions: @escaping () -> A
    ) -> some View {
        modifier(ConversationGrouping(label: label, identifier: identifier, actions: actions))
    }
}

private struct ConversationGrouping<A: View>: ViewModifier {
    let label: String
    let identifier: String
    let actions: () -> A

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private static var forced: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--a11y-group")
        #else
        return false
        #endif
    }

    func body(content: Content) -> some View {
        if voiceOver || Self.forced {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityActions(actions)
                .accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

struct ConversationReplyTarget: Equatable {
    let id: Int64
    let handle: String
    var prefill: Bool
}

/// 입력은 유리 바(DESIGN.md §1), 보내기는 솔리드 그린 원(§1.4 유리 중첩 금지).
struct ConversationComposer: View {
    @Binding var text: String
    @Binding var replyTarget: ConversationReplyTarget?
    let placeholder: LocalizedStringKey
    let replyPlaceholder: LocalizedStringKey
    let sendLabel: LocalizedStringKey
    let loginMessage: LocalizedStringKey
    var inputIdentifier = "conversation.input"
    var sendIdentifier = "conversation.send"
    var focusOnAppear = false
    var focusRequest = 0
    var onIdle: (() -> Void)?
    let send: (String) async throws -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var sending = false
    @State private var sendFailed = false
    @State private var showLoginPrompt = false
    @State private var sentPulse = 0
    @State private var calledHandle: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTarget {
                HStack(spacing: 6) {
                    Text("@\(replyTarget.handle)에게 답글")
                        .typeScale(.footnote)
                        .foregroundStyle(Palette.link)
                    Button {
                        self.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13 * unit))
                            .foregroundStyle(.secondary)
                            .expandTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("답글 취소")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("conversation.replyChip")
            }
            if sendFailed {
                Text("전송하지 못했습니다 — 다시 시도해 주세요.")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.danger)
            }
            if focused {
                MentionSuggestionList(query: MentionDraft.trailingQuery(in: text)) {
                    text = MentionDraft.complete(text, with: $0.username)
                }
            }
            HStack(alignment: .center, spacing: 10) {
                TextField(replyTarget == nil ? placeholder : replyPlaceholder, text: $text, axis: .vertical)
                    .typeScale(.body)
                    .lineLimit(1...4)
                    .focused($focused)
                    .accessibilityIdentifier(inputIdentifier)
                    .submitLabel(.send)
                    .onSubmit { if canSend { submit() } }
                Button {
                    submit()
                } label: {
                    Group {
                        if sending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15 * unit, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 34 * unit, height: 34 * unit)
                    .background(
                        canSend || sending ? GlassTokens.prominentTint : Color.secondary.opacity(0.45),
                        in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend || sending)
                .accessibilityLabel(sendLabel)
                .accessibilityIdentifier(sendIdentifier)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.radius))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .onAppear { if focusOnAppear { focused = true } }
        .onChange(of: focusRequest) { focused = true }
        .sensoryFeedback(.impact(weight: .light), trigger: sentPulse)
        .onChange(of: focused) { _, isFocused in
            guard let onIdle, !isFocused, !sending,
                  text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            replyTarget = nil
            onIdle()
        }
        .onChange(of: replyTarget, initial: true) { _, target in
            if let calledHandle, text.hasPrefix(calledHandle) {
                text.removeFirst(calledHandle.count)
            }
            calledHandle = nil
            if target != nil { focused = true }
            guard let target, target.prefill, target.handle != AuthStore.shared.me?.username else { return }
            let handle = "@\(target.handle) "
            text = handle + text
            calledHandle = handle
        }
        .loginPrompt(isPresented: $showLoginPrompt, message: loginMessage)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        guard !sending, canSend else { return }
        sendFailed = false
        sending = true
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { sending = false }
            do {
                try await send(body)
                text = ""
                calledHandle = nil
                replyTarget = nil
                focused = false
                sentPulse += 1
                onIdle?()
            } catch {
                sendFailed = true
            }
        }
    }
}
