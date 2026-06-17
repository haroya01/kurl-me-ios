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
    @State private var replies: [HighlightReplyView] = []
    @State private var text = ""
    @State private var busy = false
    /// 이 문장이 속한 공개 길/컬렉션 — A 척추 발견 고리(한 문장 → 그것이 엮인 길들로).
    @State private var inCollections: [CollectionSummary] = []

    /// 연결은 서버에 자리잡은(양수 id) 하이라이트만 — 낙관적 생성 직후(음수 id)는 refId 가 없다.
    private var canConnect: Bool { highlight.id > 0 && AuthStore.shared.isSignedIn }

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
                        Text("첫 답글을 남겨보세요.")
                            .font(.system(size: 14 * unit))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
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
                }
            }
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("하이라이트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                if canConnect {
                    // 이 문장을 내 컬렉션(연결 그래프)에 노드로 — 발견 피드로 흐르는 진입점.
                    // 시트 위 시트를 피해 닫고 나서 부모가 ConnectSheet 를 띄운다(present-after-dismiss).
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            let target = highlight
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                store.connectTarget = target
                            }
                        } label: {
                            Image(systemName: "rectangle.stack.badge.plus")
                        }
                        .accessibilityLabel(Text("컬렉션에 연결"))
                        .accessibilityIdentifier("connectHighlightButton")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loadReplies() }
        .task { await loadContainingCollections() }
    }

    /// 한 사람의 기여 = 아바타 + (이름·시각) + 본문, 바짝 뭉쳐 한 덩어리로(근접 그룹핑).
    /// 오프너(큐레이터 메모)는 이름 옆 그린 한 가닥으로 표시.
    private func personRow(
        author: Author?, date: Date?, text: String, isOpener: Bool, replyId: Int64? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(author)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isOpener {
                        Circle().fill(Palette.accent).frame(width: 5, height: 5)
                    }
                    Text("@\(author?.username ?? "?")")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.ink)
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
            HStack(alignment: .bottom, spacing: 10) {
                TextField("답글 남기기…", text: $text, axis: .vertical)
                    .font(.system(size: 15 * unit))
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Palette.chipBg, in: Capsule())
                Button { submit() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30 * unit))
                        .foregroundStyle(canSend ? Palette.accent : Palette.faint)
                        .symbolEffect(.bounce, value: busy)
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
        replies = (try? await HighlightsAPI.replies(highlightId: highlight.id)) ?? []
    }

    private func loadContainingCollections() async {
        guard highlight.id > 0 else { return }  // 낙관 생성 직후(음수 id)는 서버에 없다.
        inCollections =
            (try? await CollectionsAPI.collectionsContaining(highlightId: highlight.id)) ?? []
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
        Task {
            defer { busy = false }
            _ = try? await HighlightsAPI.reply(highlightId: highlight.id, body: trimmed)
            text = ""
            await loadReplies()
            await store.load() // replyCount 갱신 → 본문 밑줄 표식
        }
    }

    private func remove(_ id: Int64) {
        busy = true
        Task {
            defer { busy = false }
            try? await HighlightsAPI.deleteReply(id: id)
            await loadReplies()
            await store.load()
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
                    .font(.system(size: 16 * unit))
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
    }
}
