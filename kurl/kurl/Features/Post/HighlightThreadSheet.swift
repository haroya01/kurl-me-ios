//
//  HighlightThreadSheet.swift
//  kurl
//

import SwiftUI

/// 하이라이트 답글 스레드(Are.na식 여백 대화) — **앵커(인용 + 작성자 메모)는 한 덩어리로 뭉치고,
/// 그 아래 대화(답글)는 한 칸 떼어 별도 그룹으로** 읽힌다. 종이 본문(slate·아바타 hairline·그린 한
/// 가닥), 크롬(작성기·시트)은 유리. 답글은 QuietAppear 로 조용히 들어온다(§1.6).
struct HighlightThreadSheet: View {
    let highlight: HighlightView
    let store: PostHighlightStore

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var replies: [HighlightReplyView] = []
    @State private var text = ""
    @State private var noReplyTarget: ConversationReplyTarget?
    @State private var focusRequest = 0
    @State private var busy = false
    @State private var likeGen: [Int64: Int] = [:]
    @State private var showLikeLogin = false
    @State private var showDeleteConfirm = false
    /// 이 문장이 속한 공개 길/컬렉션 — A 척추 발견 고리(한 문장 → 그것이 엮인 길들로).
    @State private var inCollections: [CollectionSummary] = []
    /// 이 문장과 같은 공개 컬렉션에 함께 놓인 다른 블록 — "이것과 이어진 것"(공동 등장 발견 고리).
    @State private var related: [RelatedBlock] = []
    @State private var path = NavigationPath()

    /// 연결은 서버에 자리잡은(양수 id) 하이라이트만 — 낙관적 생성 직후(음수 id)는 refId 가 없다.
    private var canConnect: Bool { highlight.id > 0 && AuthStore.shared.isSignedIn }

    /// 내가 그은 하이라이트만 삭제 가능 — 서버에 자리잡은(양수 id) 것에 한해 소유 검사.
    private var isMine: Bool {
        guard highlight.id > 0, let myId = AuthStore.shared.me?.id else { return false }
        return highlight.author?.id == myId
    }

    /// 메모나 답글이 딸렸는지 — 삭제 확인 문구에서 "함께 사라져요" 고지를 켠다.
    private var hasThread: Bool { (highlight.note?.isEmpty == false) || highlight.replyCount > 0 }

    private var hasOpener: Bool { (highlight.note?.isEmpty == false) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── 앵커: 무엇에 대한 대화인가 (인용 + 큐레이터 메모) — 바짝 뭉친 한 덩어리.
                    VStack(alignment: .leading, spacing: hasOpener ? 14 : 0) {
                        HStack(alignment: .top, spacing: 11) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Palette.accent)
                                .frame(width: 3)
                            Text(highlight.quote)
                                .typeScale(.lede)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let note = highlight.note, !note.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("공개 메모", systemImage: "globe")
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                                ConversationRow(
                                    author: highlight.author, date: highlight.createdAt,
                                    spoken: ConversationName.spokenLine(
                                        highlight.author, date: highlight.createdAt, body: note),
                                    identifier: "highlight.opener"
                                ) {
                                    ConversationBody(text: note)
                                } actions: {
                                    EmptyView()
                                } trailing: {
                                    EmptyView()
                                } spokenActions: {
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 18)
                    .padding(.bottom, 22)

                    // ── 대화: 앵커와 한 칸 떨어진 별도 그룹. 구분은 폭 좁힌 hairline 한 가닥.
                    if !visibleReplies.isEmpty {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Metrics.gutter)
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(visibleReplies.enumerated()), id: \.element.id) { index, reply in
                                HighlightReplyRow(
                                    reply: reply, busy: busy,
                                    onLike: { toggleLike(reply.id) },
                                    onReply: { self.reply(to: $0) },
                                    onDelete: { remove(reply.id) })
                                .modifier(QuietAppear(index: min(index, 6)))
                            }
                        }
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    } else if !hasOpener {
                        // 답글 0개 — 하이라이트(따옴표+작성자)는 이미 위에 있으므로 이 자리는 "답글이
                        // 없다"만 조용히 말한다. 예전 "첫 답글 쓰기"는 큰 중앙 블록이라 "여기 비어 있다/
                        // 하이라이트 없다"로 오독됐다(웹 #893 미러) — 왼쪽 정렬 muted 한 줄로 낮춘다.
                        // 막다른 길은 아니게, 탭하면 여전히 작성기가 열린다(어포던스 유지).
                        Button {
                            focusRequest += 1
                        } label: {
                            Text("아직 답글이 없어요")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.faint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Metrics.gutter)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // ── 이 문장이 속한 길 — 한 문장에서 그것이 엮인 길/컬렉션으로(A 척추 발견 고리).
                    if !inCollections.isEmpty {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Metrics.gutter)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("이 문장이 속한 길")
                                .typeScale(.eyebrow)
                                .tracking(0.4)
                                .foregroundStyle(Palette.faint)
                            ForEach(inCollections) { c in
                                NavigationLink(value: CollectionRef(id: c.id)) {
                                    containingRow(c)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    }

                    // ── 이것과 이어진 것 — 같은 공개 컬렉션에 함께 놓인 다른 블록(공동 등장). 한 문장에서
                    // 큐레이터가 곁에 엮은 글·문장·노트로 — connect not broadcast 발견 고리.
                    if !related.isEmpty {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Metrics.gutter)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("이것과 이어진 것")
                                .typeScale(.eyebrow)
                                .tracking(0.4)
                                .foregroundStyle(Palette.faint)
                            ForEach(related) { item in
                                BlockPreview(block: item.block)
                            }
                        }
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id)
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .environment(\.openURL, OpenURLAction { url in
                guard case let .member(username)? = NoteText.target(from: url) else { return .systemAction }
                path.append(Route.author(username: username))
                return .handled
            })
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("대화")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                if isMine {
                    // 내 하이라이트 — 연결과 삭제를 한 메뉴로(컬렉션 상세와 같은 ellipsis 관리 문법).
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                startConnect()
                            } label: {
                                Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
                            }
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("하이라이트 삭제", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .tint(.brand)
                        .accessibilityLabel(Text("하이라이트 관리"))
                        .accessibilityIdentifier("highlightManageMenu")
                    }
                } else if canConnect {
                    // 남의 문장 — 내 컬렉션(연결 그래프)에 노드로 잇는 진입점.
                    // 시트 위 시트를 피해 닫고 나서 부모가 ConnectSheet 를 띄운다(present-after-dismiss).
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            startConnect()
                        } label: {
                            Image(systemName: "rectangle.stack.badge.plus")
                        }
                        .accessibilityLabel(Text("컬렉션에 연결"))
                        .accessibilityIdentifier("connectHighlightButton")
                    }
                }
            }
            .alert("이 하이라이트를 삭제할까요?", isPresented: $showDeleteConfirm) {
                Button("삭제", role: .destructive) { performDelete() }
                Button("취소", role: .cancel) {}
            } message: {
                Text(hasThread
                    ? "남긴 메모와 답글도 함께 사라져요. 되돌릴 수 없어요."
                    : "삭제하면 되돌릴 수 없어요.")
            }
        }
        .modifier(ToastHost())
        .loginPrompt(isPresented: $showLikeLogin, message: "좋아요를 누르려면 로그인하세요")
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // 답글을 쓰던 중의 드래그 닫힘은 입력을 통째로 버린다 — 글자가 있는 동안만 잠근다
        // (보내거나 지우면 다시 닫힘, 인증 시트와 같은 관용구).
        .interactiveDismissDisabled(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .task { await loadReplies() }
        .task { await loadContainingCollections() }
        .task { await loadRelated() }
    }

    /// 차단한 사람의 답글은 숨긴다(App Store 1.2 — 글 댓글과 같은 규칙).
    private var visibleReplies: [HighlightReplyView] {
        replies.filter { reply in reply.author.map { !BlockStore.shared.isBlocked($0.username) } ?? true }
    }

    private var composer: some View {
        ConversationComposer(
            text: $text,
            replyTarget: $noReplyTarget,
            placeholder: "답글을 남겨보세요",
            replyPlaceholder: "답글을 남겨보세요",
            sendLabel: "답글 보내기",
            loginMessage: "답글을 달려면 로그인하세요",
            inputIdentifier: "highlightReply.field",
            sendIdentifier: "highlightReply.send",
            focusRequest: focusRequest
        ) { body in
            _ = try await HighlightsAPI.reply(highlightId: highlight.id, body: body)
            await loadReplies()
            await store.load() // replyCount 갱신 → 본문 밑줄 표식
        }
    }

    private func toggleLike(_ id: Int64) {
        guard AuthStore.shared.isSignedIn else {
            showLikeLogin = true
            return
        }
        guard let current = replies.first(where: { $0.id == id }) else { return }
        let on = !(current.liked ?? false)
        let gen = (likeGen[id] ?? 0) + 1
        likeGen[id] = gen
        setLike(id, on: on, count: max(0, (current.likeCount ?? 0) + (on ? 1 : -1)))
        Task {
            do {
                let status = try await HighlightsAPI.setReplyLike(id: id, on: on)
                guard likeGen[id] == gen else { return }
                setLike(id, on: status.liked, count: status.likeCount)
            } catch {
                guard likeGen[id] == gen else { return }
                setLike(id, on: !on, count: current.likeCount ?? 0)
                ToastCenter.shared.show(String(localized: "좋아요를 반영하지 못했어요"))
            }
        }
    }

    private func setLike(_ id: Int64, on: Bool, count: Int64) {
        guard let index = replies.firstIndex(where: { $0.id == id }) else { return }
        replies[index].liked = on
        replies[index].likeCount = count
    }

    private func reply(to handle: String) {
        let mention = "@\(handle) "
        if !text.hasPrefix(mention) { text = mention + text }
        focusRequest += 1
    }

    private func loadReplies() async {
        // 재조회 실패가 이미 떠 있는 스레드를 지우지 않도록 — 성공했을 때만 교체.
        if let fetched = try? await HighlightsAPI.replies(highlightId: highlight.id) {
            replies = fetched
        }
    }

    private func loadContainingCollections() async {
        guard highlight.id > 0 else { return }  // 낙관 생성 직후(음수 id)는 서버에 없다.
        inCollections =
            (try? await CollectionsAPI.collectionsContaining(highlightId: highlight.id)) ?? []
    }

    private func loadRelated() async {
        guard highlight.id > 0 else { return }
        related =
            (try? await CollectionsAPI.relatedBlocks(blockType: "HIGHLIGHT", refId: highlight.id))
            ?? []
    }

    /// "이 문장이 속한 길" 한 줄 — 길 글리프(또는 컬렉션) + 제목 + 담긴 수.
    private func containingRow(_ c: CollectionSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: c.kind == .path ? "arrow.turn.down.right" : "square.grid.2x2")
                .font(.system(size: 12 * metaUnit, weight: .bold))
                .foregroundStyle(Palette.accent)
            Text(c.title)
                .typeScale(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(c.count)")
                .typeScale(.meta)
                .foregroundStyle(Palette.faint)
            Image(systemName: "chevron.right")
                .font(.system(size: 11 * metaUnit, weight: .semibold))
                .foregroundStyle(Palette.faint)
        }
        .contentShape(Rectangle())
    }

    private func remove(_ id: Int64) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await HighlightsAPI.deleteReply(id: id)
                await loadReplies()
                await store.load()
            } catch {
                ToastCenter.shared.show(String(localized: "답글을 삭제하지 못했습니다"))
            }
        }
    }

    /// 이 문장을 내 컬렉션(연결 그래프)에 노드로 — 시트 위 시트를 피해, 예약만 걸고 닫는다.
    /// 실제 프레젠테이션은 부모의 onDismiss(해제 완료 시점)가 승격한다.
    private func startConnect() {
        store.pendingConnect = highlight
        dismiss()
    }

    /// 삭제 확정 — 스토어가 낙관적으로 본문에서 걷어내고, 성공하면 시트를 닫는다. 실패하면
    /// 스토어가 마크를 되살리고 토스트로 알린다.
    private func performDelete() {
        busy = true
        Task {
            defer { busy = false }
            if await store.delete(id: highlight.id) {
                dismiss()
            } else {
                ToastCenter.shared.show(String(localized: "하이라이트를 삭제하지 못했습니다"))
            }
        }
    }
}

private struct HighlightReplyRow: View {
    let reply: HighlightReplyView
    let busy: Bool
    let onLike: () -> Void
    let onReply: (String) -> Void
    let onDelete: () -> Void

    @State private var showReport = false
    @State private var showBlockConfirm = false
    @State private var likeTaps = 0

    private var isMine: Bool {
        guard let myId = AuthStore.shared.me?.id, reply.id > 0 else { return false }
        return reply.author?.id == myId
    }

    private var liked: Bool { reply.liked ?? false }
    private var likeCount: Int64 { reply.likeCount ?? 0 }

    private var other: Author? {
        guard AuthStore.shared.isSignedIn, !isMine else { return nil }
        return reply.author
    }

    var body: some View {
        ConversationRow(
            author: reply.author, date: reply.createdAt,
            spoken: ConversationName.spokenLine(
                reply.author, date: reply.createdAt, body: reply.body, likes: likeCount),
            identifier: "highlightReply.\(reply.id)"
        ) {
            ConversationBody(text: reply.body, mentions: reply.mentions ?? [])
        } actions: {
            ConversationLikeButton(liked: liked, count: likeCount, action: like)
                .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
                .accessibilityIdentifier("highlightReply.like.\(reply.id)")
            if let other {
                ConversationReplyButton { onReply(other.username) }
                    .accessibilityIdentifier("highlightReply.reply.\(reply.id)")
            }
        } trailing: {
            if isMine {
                Button(action: onDelete) { ConversationIcon(systemName: "trash") }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityLabel("답글 삭제")
                    .accessibilityIdentifier("highlightReply.delete.\(reply.id)")
            } else {
                Menu {
                    if other != nil {
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label("차단", systemImage: "hand.raised")
                        }
                    }
                    Button(role: .destructive) { showReport = true } label: {
                        Label("신고", systemImage: "flag")
                    }
                } label: {
                    ConversationIcon(systemName: "ellipsis")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("답글 메뉴")
                .accessibilityIdentifier("highlightReply.more.\(reply.id)")
            }
        } spokenActions: {
            Button(liked ? LocalizedStringKey("좋아요 취소") : LocalizedStringKey("좋아요"), action: like)
            if let other {
                Button("답글") { onReply(other.username) }
                Button("차단") { showBlockConfirm = true }
            }
            if isMine {
                Button("삭제", action: onDelete)
            } else {
                Button("신고") { showReport = true }
            }
        }
        .reportDialog(isPresented: $showReport, subjectType: "HIGHLIGHT_REPLY", subjectId: reply.id)
        .blockDialog(
            isPresented: $showBlockConfirm,
            username: reply.author?.username ?? "", userId: reply.author?.id ?? 0)
    }

    private func like() {
        if AuthStore.shared.isSignedIn { likeTaps += 1 }
        onLike()
    }
}

/// Keeps the exact memo through a failed request and serializes retries. The sheet only dismisses
/// after this returns success; a pending save never clears input or reports a saved state.
@MainActor
@Observable
final class HighlightNoteSubmission {
    var text = ""
    private(set) var busy = false
    private(set) var errorMessage: String?
    var noteLength: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }
    var canSave: Bool { !busy && noteLength > 0 && noteLength <= HighlightsAPI.maxNoteLength }

    func save(using save: @MainActor (String) async throws -> Void) async -> Bool {
        let memo = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !memo.isEmpty else { return false }
        guard noteLength <= HighlightsAPI.maxNoteLength else {
            errorMessage = HighlightValidationError.noteTooLong.localizedDescription
            return false
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await save(memo)
            return true
        } catch {
            if let validation = error as? HighlightValidationError {
                errorMessage = validation.localizedDescription
            } else if let authError = error as? AuthError, case .notSignedIn = authError {
                errorMessage = String(localized: "로그인이 필요해요. 작성한 메모는 그대로 남아 있어요.")
            } else {
                errorMessage = String(localized: "메모를 저장하지 못했어요. 입력은 그대로 남아 있어요.")
            }
            return false
        }
    }
}

/// 메모와 함께 하이라이트 — 공개 범위를 확인하고, 저장 성공 뒤 읽던 자리로 돌아간다.
struct HighlightNoteComposerSheet: View {
    let draft: PostHighlightStore.NoteDraft
    let onSave: @MainActor (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var submission = HighlightNoteSubmission()
    @State private var showDiscardConfirm = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("이 글의 독자에게 공개돼요", systemImage: "globe")
                            .typeScale(.footnote)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("highlightNoteVisibility")

                        // The source and the thought share one paper surface. Keep the writing
                        // area flexible so the space above the keyboard belongs to the memo.
                        VStack(alignment: .leading, spacing: 12) {
                            Text(draft.quote)
                                .typeScale(.lede)
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 14)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(Palette.accent)
                                        .frame(width: 3)
                                }
                                .accessibilityLabel(Text(verbatim: draft.quote))
                                .accessibilityIdentifier("highlightNoteQuote")

                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(height: 1)
                                .accessibilityHidden(true)

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $submission.text)
                                    .typeScale(.body)
                                    .scrollContentBackground(.hidden)
                                    .focused($focused)
                                    .disabled(submission.busy)
                                    .accessibilityLabel(Text("이 부분에 대한 메모를 남겨보세요"))
                                    .accessibilityIdentifier("highlightNoteInput")

                                if submission.text.isEmpty {
                                    Text("이 부분에 대한 메모를 남겨보세요")
                                        .typeScale(.body)
                                        .foregroundStyle(Palette.faint)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: 140, maxHeight: .infinity)
                        }
                        .frame(maxHeight: .infinity)

                        if submission.noteLength >= 400 {
                            Text("\(submission.noteLength)/500")
                                .typeScale(.meta)
                                .monospacedDigit()
                                .foregroundStyle(submission.noteLength > HighlightsAPI.maxNoteLength ? Palette.danger : Palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if let message = submission.noteLength > HighlightsAPI.maxNoteLength
                            ? HighlightValidationError.noteTooLong.errorDescription : submission.errorMessage {
                            Text(message)
                                .typeScale(.footnote)
                                .foregroundStyle(Palette.danger)
                                .accessibilityIdentifier("highlightNoteSaveError")
                        }
                    }
                    .padding(Metrics.gutter)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .frame(maxWidth: Metrics.readingColumn)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("메모 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if submission.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            dismiss()
                        } else {
                            showDiscardConfirm = true
                        }
                    }
                    .disabled(submission.busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await submission.save(using: onSave) { dismiss() }
                        }
                    } label: {
                        if submission.busy {
                            ProgressView().accessibilityLabel(Text("저장 중"))
                        } else if submission.errorMessage != nil {
                            Text("다시 저장")
                        } else {
                            Text("저장")
                        }
                    }
                    .disabled(!submission.canSave)
                    .accessibilityIdentifier("saveHighlightNote")
                }
            }
            .confirmationDialog("작성한 메모를 버릴까요?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("메모 버리기", role: .destructive) { dismiss() }
                Button("계속 쓰기", role: .cancel) {}
            }
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                focused = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // 메모를 쓰다 드래그로 내리면 유실 — 글자가 있는 동안만 잠근다(취소 버튼은 그대로 출구).
        .interactiveDismissDisabled(submission.busy || !submission.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
