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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    /// 답글 작성기 포커스 — 빈 스레드의 '첫 답글 쓰기' 어포던스가 이 포커스를 세운다.
    @FocusState private var composerFocused: Bool
    @State private var replies: [HighlightReplyView] = []
    @State private var text = ""
    @State private var busy = false
    @State private var sendFailed = false
    @State private var showDeleteConfirm = false
    /// 이 문장이 속한 공개 길/컬렉션 — A 척추 발견 고리(한 문장 → 그것이 엮인 길들로).
    @State private var inCollections: [CollectionSummary] = []
    /// 이 문장과 같은 공개 컬렉션에 함께 놓인 다른 블록 — "이것과 이어진 것"(공동 등장 발견 고리).
    @State private var related: [RelatedBlock] = []

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
        NavigationStack {
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
                            personRow(author: highlight.author, date: highlight.createdAt, text: note, isOpener: true)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 18)
                    .padding(.bottom, 22)

                    // ── 대화: 앵커와 한 칸 떨어진 별도 그룹. 구분은 폭 좁힌 hairline 한 가닥.
                    if !replies.isEmpty {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Metrics.gutter)
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                                personRow(
                                    author: reply.author, date: reply.createdAt, text: reply.body,
                                    isOpener: false, replyId: reply.id
                                )
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
                            composerFocused = true
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
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("하이라이트")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // 답글을 쓰던 중의 드래그 닫힘은 입력을 통째로 버린다 — 글자가 있는 동안만 잠근다
        // (보내거나 지우면 다시 닫힘, 인증 시트와 같은 관용구).
        .interactiveDismissDisabled(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .task { await loadReplies() }
        .task { await loadContainingCollections() }
        .task { await loadRelated() }
    }

    /// 한 사람의 기여 = 아바타 + (이름·시각) + 본문, 바짝 뭉쳐 한 덩어리로(근접 그룹핑).
    /// 오프너(큐레이터 메모)는 이름 옆 그린 한 가닥으로 표시.
    private func personRow(
        author: Author?, date: Date?, text: String, isOpener: Bool, replyId: Int64? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 아바타·이름 → 그 사람 프로필(있을 때). 시트 안 스택에 push 된다.
            if let author {
                NavigationLink(value: Route.author(username: author.username)) {
                    avatar(author)
                }
                .buttonStyle(.plain)
            } else {
                avatar(author)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isOpener {
                        Circle().fill(Palette.accent).frame(width: 5, height: 5)
                    }
                    if let author {
                        NavigationLink(value: Route.author(username: author.username)) {
                            Text("@\(author.username)")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.ink)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("@?")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.ink)
                    }
                    if let date {
                        Text(date.formatted(.dateTime.month().day()))
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                    if let replyId, isMyReply(replyId) {
                        Button { remove(replyId) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12 * metaUnit))
                                .foregroundStyle(Palette.secondary)
                                .expandTapTarget()  // 12pt 아이콘 → 44pt 터치 타깃
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel(Text("답글 삭제"))
                    }
                }
                Text(text)
                    .typeScale(.body)
                    .foregroundStyle(Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func avatar(_ author: Author?) -> some View {
        if let author {
            AvatarView(author: author, size: 26 * metaUnit)
        } else {
            Circle().fill(Palette.chipBg).frame(width: 26 * metaUnit, height: 26 * metaUnit)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            if sendFailed {
                Text("전송하지 못했습니다 — 다시 시도해 주세요.")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 10)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("답글 남기기…", text: $text, axis: .vertical)
                    .focused($composerFocused)
                    .typeScale(.body)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.chipBg, in: Capsule())
                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30 * unit))
                        .foregroundStyle(canSend ? Palette.accent : Palette.faint)
                        .symbolEffect(.bounce, value: reduceMotion ? false : busy)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || busy)
                .scaleEffect(canSend ? 1 : 0.92)
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: canSend)
                .accessibilityLabel(Text("답글 보내기"))
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 11)
        }
        .background(.bar)
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func isMyReply(_ replyId: Int64) -> Bool {
        guard let myId = AuthStore.shared.me?.id, replyId > 0 else { return false }
        return replies.first(where: { $0.id == replyId })?.author?.id == myId
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

    private func submit() {
        guard AuthStore.shared.isSignedIn else {
            dismiss()
            store.loginPrompt = true
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        busy = true
        sendFailed = false
        Task {
            defer { busy = false }
            do {
                _ = try await HighlightsAPI.reply(highlightId: highlight.id, body: trimmed)
                text = ""
                await loadReplies()
                await store.load() // replyCount 갱신 → 본문 밑줄 표식
            } catch {
                sendFailed = true // 입력은 보존 — 실패를 보이게.
            }
        }
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

/// 메모와 함께 하이라이트 — 선택 구간에 작성자의 여백 노트(스레드 오프너)를 달아 생성한다.
struct HighlightNoteComposerSheet: View {
    let draft: PostHighlightStore.NoteDraft
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // 무엇에 메모하나 — 인용을 그린 한 가닥과 함께 바짝 위에.
                HStack(alignment: .top, spacing: 11) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Palette.accent)
                        .frame(width: 3)
                    Text(draft.quote)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField("이 부분에 대한 메모를 남겨보세요", text: $note, axis: .vertical)
                    .typeScale(.body)
                    .lineLimit(3...7)
                    .focused($focused)
                    .padding(14)
                    .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
                Spacer(minLength: 0)
            }
            .padding(Metrics.gutter)
            .navigationTitle("메모 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { onSave(note); dismiss() }
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                focused = true
            }
        }
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
        // 메모를 쓰다 드래그로 내리면 유실 — 글자가 있는 동안만 잠근다(취소 버튼은 그대로 출구).
        .interactiveDismissDisabled(!note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
