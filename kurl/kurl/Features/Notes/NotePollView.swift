//
//  NotePollView.swift
//  kurl
//

import SwiftUI

struct NotePollView: View {
    let noteId: Int64
    let poll: NotePoll
    let onVoted: (NotePoll) -> Void

    @State private var picked: Set<Int> = []
    @State private var peeking = false
    @State private var voting = false
    @State private var filled: Bool
    @State private var showLogin = false
    @State private var votedTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(noteId: Int64, poll: NotePoll, onVoted: @escaping (NotePoll) -> Void) {
        self.noteId = noteId
        self.poll = poll
        self.onVoted = onVoted
        _filled = State(initialValue: poll.voted == true || Self.isClosed(poll))
    }

    private static func isClosed(_ poll: NotePoll) -> Bool {
        poll.expired || (poll.expiresAt.map { $0 <= .now } ?? false)
    }

    private var closed: Bool { Self.isClosed(poll) }
    private var showsResults: Bool { poll.voted == true || closed || peeking }
    private var leading: Int64 { poll.options.map(\.votesCount).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                if showsResults {
                    result(index, option)
                } else {
                    choice(index, option)
                }
            }
            if !showsResults, poll.multiple {
                Button {
                    Task { await vote(picked.sorted()) }
                } label: {
                    Text("투표")
                        .typeScale(.meta)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(Palette.link)
                .disabled(picked.isEmpty || voting)
                .accessibilityIdentifier("note.poll.vote.\(noteId)")
            }
            footer
        }
        .sensoryFeedback(.success, trigger: votedTick)
        .loginPrompt(isPresented: $showLogin, message: "투표에 참여하기")
        .onChange(of: showsResults) { _, shows in
            guard shows else {
                filled = false
                return
            }
            filled = false
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.45)) { filled = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note.poll.\(noteId)")
    }

    private func choice(_ index: Int, _ option: NotePoll.Option) -> some View {
        let on = picked.contains(index)
        return Button {
            guard AuthStore.shared.isSignedIn else {
                showLogin = true
                return
            }
            if poll.multiple {
                if on { picked.remove(index) } else { picked.insert(index) }
            } else {
                Task { await vote([index]) }
            }
        } label: {
            HStack(spacing: 10) {
                if poll.multiple {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(on ? Palette.link : Palette.secondary)
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .typeScale(.note)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(on ? Palette.link : Palette.hairlineStrong, lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
        }
        .buttonStyle(.plain)
        .disabled(voting)
        .accessibilityAddTraits(poll.multiple && on ? .isSelected : [])
        // 단일 선택은 탭이 곧 투표이고 되돌릴 수 없다 — 눈으로는 즉시 결과로 바뀌어 알지만 VoiceOver 는 미리 알아야 한다.
        .accessibilityHint(poll.multiple ? Text("선택한 뒤 투표 버튼을 눌러요") : Text("탭하면 바로 투표돼요"))
        .accessibilityIdentifier("note.poll.option.\(noteId).\(index)")
    }

    private func result(_ index: Int, _ option: NotePoll.Option) -> some View {
        let share = poll.share(of: option)
        let mine = poll.ownVotes?.contains(index) == true
        let top = leading > 0 && option.votesCount == leading
        return HStack(spacing: 6) {
            Text(option.title)
                .typeScale(.note)
                .fontWeight(top ? .semibold : .regular)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
            if mine {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.link)
                    .accessibilityLabel("내 선택")
            }
            Spacer(minLength: 8)
            Text(share, format: .percent.precision(.fractionLength(0)))
                .typeScale(.meta)
                .fontWeight(top ? .bold : .medium)
                .monospacedDigit()
                .foregroundStyle(top ? Palette.ink : Palette.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .strokeBorder(Palette.hairlineStrong.opacity(0.6)))
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(top ? Palette.accentSoft.opacity(0.32) : Palette.chipBg)
                    .frame(width: filled ? max(geo.size.width * share, share > 0 ? 6 : 0) : 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("note.poll.result.\(noteId).\(index)")
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("\(poll.votersCount)명 참여")
            Text(verbatim: "·")
            Text(remaining)
            if poll.voted != true, !closed {
                Text(verbatim: "·")
                Button(peeking ? LocalizedStringKey("투표로 돌아가기") : LocalizedStringKey("결과 보기")) {
                    peeking.toggle()
                }
                .buttonStyle(.plain)
                .underline()
                .accessibilityIdentifier("note.poll.peek.\(noteId)")
            }
        }
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
        .padding(.top, 2)
    }

    private var remaining: LocalizedStringKey {
        guard !poll.expired, let end = poll.expiresAt else { return "마감됨" }
        let seconds = end.timeIntervalSinceNow
        if seconds <= 0 { return "마감됨" }
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))분 남음" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))시간 남음" }
        return "\(Int(seconds / 86_400))일 남음"
    }

    private func vote(_ choices: [Int]) async {
        guard !choices.isEmpty, !voting else { return }
        voting = true
        defer { voting = false }
        do {
            let updated = try await NoteAPI.vote(id: noteId, choices: choices)
            votedTick += 1
            peeking = false
            picked = []
            onVoted(updated)
        } catch APIError.server(let status, _, _) where status == 409 {
            ToastCenter.shared.show(String(localized: "이미 투표한 투표예요"))
        } catch {
            ToastCenter.shared.show(String(localized: "투표하지 못했어요"))
        }
    }
}

enum NotePollDuration: Int, CaseIterable, Identifiable {
    case fiveMinutes = 300
    case thirtyMinutes = 1800
    case hour = 3600
    case sixHours = 21_600
    case twelveHours = 43_200
    case day = 86_400
    case threeDays = 259_200
    case week = 604_800

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .fiveMinutes: "5분"
        case .thirtyMinutes: "30분"
        case .hour: "1시간"
        case .sixHours: "6시간"
        case .twelveHours: "12시간"
        case .day: "1일"
        case .threeDays: "3일"
        case .week: "7일"
        }
    }
}

struct NotePollDraft: Equatable {
    struct Choice: Identifiable, Equatable {
        let id = UUID()
        var text = ""
    }

    var choices: [Choice] = [Choice(), Choice()]
    var duration: NotePollDuration = .day
    var multiple = false

    var options: [String] { choices.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } }

    var isValid: Bool {
        let options = options
        return options.count >= 2
            && options.allSatisfy { !$0.isEmpty && $0.count <= NoteAPI.maxPollOptionLength }
            && Set(options).count == options.count
    }

    var request: NoteDraft.Poll {
        NoteDraft.Poll(options: options, expiresIn: duration.rawValue, multiple: multiple)
    }
}

struct NotePollEditor: View {
    @Binding var draft: NotePollDraft
    @FocusState private var focused: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($draft.choices) { $choice in
                let index = draft.choices.firstIndex { $0.id == choice.id } ?? 0
                HStack(spacing: 8) {
                    TextField("선택지 \(index + 1)", text: $choice.text)
                        .typeScale(.note)
                        .focused($focused, equals: choice.id)
                        .submitLabel(index + 1 < draft.choices.count ? .next : .done)
                        .onSubmit {
                            focused = index + 1 < draft.choices.count ? draft.choices[index + 1].id : nil
                        }
                        .onChange(of: choice.text) { _, text in
                            if text.count > NoteAPI.maxPollOptionLength {
                                choice.text = String(text.prefix(NoteAPI.maxPollOptionLength))
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.radius)
                                .strokeBorder(focused == choice.id ? Palette.link : Palette.hairlineStrong))
                        .accessibilityIdentifier("noteCompose.poll.option.\(index)")
                    if draft.choices.count > 2 {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                draft.choices.removeAll { $0.id == choice.id }
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 17))
                                .foregroundStyle(Palette.secondary)
                                .frame(width: 28, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("선택지 빼기")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 14) {
                if draft.choices.count < NoteAPI.maxPollOptions {
                    Button {
                        let choice = NotePollDraft.Choice()
                        withAnimation(.snappy(duration: 0.2)) { draft.choices.append(choice) }
                        focused = choice.id
                    } label: {
                        Label("선택지 추가", systemImage: "plus")
                    }
                    .accessibilityIdentifier("noteCompose.poll.add")
                }
                Spacer(minLength: 0)
                Menu {
                    Picker("기간", selection: $draft.duration) {
                        ForEach(NotePollDuration.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label { Text(draft.duration.title) } icon: { Image(systemName: "clock") }
                }
                .accessibilityIdentifier("noteCompose.poll.duration")
                Button {
                    draft.multiple.toggle()
                } label: {
                    Label("여러 개 선택", systemImage: draft.multiple ? "checkmark.square.fill" : "square")
                }
                .accessibilityAddTraits(draft.multiple ? .isSelected : [])
                .accessibilityIdentifier("noteCompose.poll.multiple")
            }
            .typeScale(.meta)
            .fontWeight(.medium)
            .tint(Palette.link)
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondary)
            .padding(.top, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .strokeBorder(Palette.hairlineStrong))
        .onAppear { focused = draft.choices.first?.id }
    }
}
