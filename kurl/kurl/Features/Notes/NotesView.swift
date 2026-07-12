//
//  NotesView.swift
//  kurl
//

import Observation
import SwiftUI

/// 짧은 글 피드 — 제목 없는 생각의 줄. 글(post)의 격식 없이 한 단락을 흘리는 자리라
/// 카드가 아니라 가벼운 대화 행(헤어라인 구분). 작성은 하단 유리 바(로그인 시),
/// 좋아요는 낙관 토글.
@MainActor
@Observable
final class NotesViewModel {
    private(set) var items: [Note] = []
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var likedIds: Set<Int64> = []
    private(set) var isLoadingMore = false

    /// 낙관 카운트 보정 — 서버 응답이 오기 전의 표시값.
    private var countOverride: [Int64: Int64] = [:]
    private var toggleGen: [Int64: Int] = [:]
    private var page = 0
    private var hasNext = true
    private var epoch = 0

    func displayLikeCount(_ note: Note) -> Int64 {
        countOverride[note.id] ?? note.likeCount
    }

    func isLiked(_ note: Note) -> Bool {
        likedIds.contains(note.id)
    }

    func loadInitial() async {
        guard case .idle = phase else { return }
        await reload()
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty { phase = .loading }
        do {
            let view = try await NoteAPI.feed(page: 0)
            guard myEpoch == epoch else { return }
            page = 0
            items = view.items
            hasNext = view.hasNext
            countOverride = [:]
            // 첫 페이지는 합집합이 아니라 교체 — 새로고침으로 사라진 노트의 좋아요가 남지 않게.
            likedIds = []
            phase = .loaded(true)
            await hydrateLikes(for: view.items)
        } catch {
            if items.isEmpty {
                phase = .failed(
                    (error as? APIError)?.localizedDescription ?? error.localizedDescription)
            } else {
                // 이미 글이 떠 있으면 화면을 비우지 않는다 — 무음 실패 대신 토스트로 알린다.
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
        }
    }

    func loadMoreIfNeeded(current note: Note) async {
        guard hasNext, !isLoadingMore, items.last?.id == note.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let myEpoch = epoch
        if let view = try? await NoteAPI.feed(page: page + 1) {
            guard myEpoch == epoch else { return }
            page += 1
            hasNext = view.hasNext
            let seen = Set(items.map(\.id))
            items.append(contentsOf: view.items.filter { !seen.contains($0.id) })
            await hydrateLikes(for: view.items)
        }
    }

    private func hydrateLikes(for notes: [Note]) async {
        guard AuthStore.shared.isSignedIn else { return }
        if let ids = try? await NoteAPI.likedIds(notes.map(\.id)) {
            likedIds.formUnion(ids)
        }
    }

    func toggleLike(_ note: Note) async {
        let gen = (toggleGen[note.id] ?? 0) + 1
        toggleGen[note.id] = gen
        let target = !isLiked(note)
        if target { likedIds.insert(note.id) } else { likedIds.remove(note.id) }
        countOverride[note.id] = displayLikeCount(note) + (target ? 1 : -1)
        do {
            let status = try await NoteAPI.setLike(id: note.id, on: target)
            guard toggleGen[note.id] == gen else { return }
            countOverride[note.id] = status.likeCount
            if status.liked { likedIds.insert(note.id) } else { likedIds.remove(note.id) }
        } catch {
            guard toggleGen[note.id] == gen else { return }
            if target { likedIds.remove(note.id) } else { likedIds.insert(note.id) }
            countOverride[note.id] = displayLikeCount(note) + (target ? -1 : 1)
            ToastCenter.shared.show(String(localized: "좋아요를 반영하지 못했습니다"))
        }
    }

    func publish(body: String) async throws {
        let created = try await NoteAPI.create(body: body)
        withAnimation(.snappy(duration: 0.3)) {
            // .loading/.failed 면 list 가 안 떠 삽입한 노트가 안 보이고 성공 햅틱만 거짓으로 울린다 —
            // 삽입 전에 .loaded 로 올려 방금 쓴 글이 곧장 보이게.
            phase = .loaded(true)
            items.insert(created, at: 0)
        }
    }

    func delete(_ note: Note) async {
        do {
            try await NoteAPI.delete(id: note.id)
            _ = withAnimation(.snappy(duration: 0.25)) {
                items.removeAll { $0.id == note.id }
            }
        } catch {
            ToastCenter.shared.show(String(localized: "노트를 삭제하지 못했습니다"))
        }
    }
}

struct NotesPage: View {
    let active: Bool
    @State private var model = NotesViewModel()
    @State private var connectNote: Note?
    @State private var showLoginSheet = false
    /// 빈 상태 CTA → 하단 컴포저 포커스. 값이 바뀔 때마다 컴포저가 필드를 연다.
    @State private var focusComposer = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") { Task { await model.reload() } }
                        .foregroundStyle(Palette.accent)
                }
            case .loaded:
                list
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 컴포저는 list 가 떴을 때만 — 로딩 마크·실패 화면 위에 떠서 안 보이는 곳에 글을 쓰지 않게.
            if active, AuthStore.shared.isSignedIn, case .loaded = model.phase {
                NoteComposerBar(focusSignal: focusComposer) { body in
                    try await model.publish(body: body)
                }
            }
        }
        .navigationTitle("노트")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $connectNote) { n in
            ConnectSheet(
                targetKind: "노트", targetTitle: n.body, blockType: .note, refId: n.id)
        }
        .loginPrompt(isPresented: $showLoginSheet, message: "첫 노트 남기기")
        .task { await model.loadInitial() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, note in
                    NoteRowView(model: model, note: note)
                        .contextMenu {
                            if AuthStore.shared.isSignedIn {
                                Button {
                                    connectNote = note
                                } label: {
                                    Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
                                }
                            }
                        }
                        .modifier(QuietAppear(index: index))
                        .transition(
                            reduceMotion
                                ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        .task { await model.loadMoreIfNeeded(current: note) }
                    if index < model.items.count - 1 { Hairline() }
                }
                if model.isLoadingMore {
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                if model.items.isEmpty {
                    // 막다른 길 금지 — 빈 노트 피드는 곧장 첫 글로 이어준다. 로그인 상태면 하단
                    // 컴포저를 열고, 아니면 로그인 시트로(FeedPlaceholder 와 같은 언어).
                    if AuthStore.shared.isSignedIn {
                        FeedPlaceholder(
                            eyebrow: "노트",
                            title: "첫 생각을 남겨보세요",
                            message: "제목도 형식도 없이, 지금 떠오른 한 줄을 흘려 두는 자리예요.",
                            actionTitle: "첫 노트 쓰기",
                            prominent: true,
                            action: { focusComposer += 1 }
                        )
                        .padding(.top, 72)
                    } else {
                        FeedPlaceholder(
                            eyebrow: "노트",
                            title: "첫 생각을 남겨보세요",
                            message: "로그인하면 제목도 형식도 없이 지금 떠오른 한 줄을 여기에 흘려 둘 수 있어요.",
                            actionTitle: "로그인",
                            prominent: true,
                            action: { showLoginSheet = true }
                        )
                        .padding(.top, 72)
                    }
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await model.reload() }
    }
}

private struct NoteRowView: View {
    let model: NotesViewModel
    let note: Note
    @State private var likeTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMine: Bool {
        AuthStore.shared.me?.id == note.author.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            NavigationLink(value: Route.author(username: note.author.username)) {
                AvatarView(author: note.author, size: 38)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(note.author.username)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.ink)
                        if let date = note.createdAt {
                            Text(date.relativeShort)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(note.body)
                        .typeScale(.body)
                        .foregroundStyle(Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 이름·시각·본문이 한 번에 읽히게 — 행이 5조각으로 흩어지지 않는다.
                .accessibilityElement(children: .combine)
                Button {
                    likeTaps += 1
                    Task { await model.toggleLike(note) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.isLiked(note) ? "heart.fill" : "heart")
                            .font(.system(size: 13))
                            .symbolEffect(
                                .bounce, value: reduceMotion ? false : model.isLiked(note))
                        if model.displayLikeCount(note) > 0 {
                            Text("\(model.displayLikeCount(note))")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    // 카운트는 메타 사다리로 — raw 12pt 산발 종식(Dynamic Type 도 따라온다). 하트는 자체 size 유지.
                    .typeScale(.meta)
                    // 종이 위 비텍스트 마커라 accent(600) — link(700)는 텍스트/인라인 CTA 자리.
                    .foregroundStyle(model.isLiked(note) ? Palette.accent : Palette.secondary)
                    .expandTapTarget()
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
                // 상태는 라벨 뒤집기가 아니라 값·트레잇으로 — 카운트도 들리게.
                .accessibilityLabel(Text("좋아요"))
                .accessibilityValue(Text("\(model.displayLikeCount(note))"))
                .accessibilityAddTraits(model.isLiked(note) ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .contextMenu {
            if isMine {
                Button(role: .destructive) {
                    Task { await model.delete(note) }
                } label: {
                    Label("노트 삭제", systemImage: "trash")
                }
            }
        }
    }
}

/// 노트 작성 — 키보드 위 유리 바(댓글 바와 같은 문법). 500자 제한, 보내면 맨 위에 꽂힌다.
private struct NoteComposerBar: View {
    /// 빈 상태 CTA 가 이 값을 올리면 필드에 포커스를 준다(초기 0 은 무시).
    var focusSignal: Int = 0
    let publish: (String) async throws -> Void

    @State private var body_ = ""
    @State private var sending = false
    @State private var sentCount = 0
    @FocusState private var focused: Bool
    /// 글자수 카운트다운 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var countdownSize: CGFloat = 11

    private var trimmed: String {
        body_.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("지금 떠오른 생각은…", text: $body_, axis: .vertical)
                .typeScale(.body)
                .lineLimit(1...4)
                .focused($focused)
            if body_.count > 400 {
                Text("\(500 - body_.count)")
                    .font(.system(size: countdownSize).monospacedDigit())
                    // 유리 위 = 시맨틱 vibrancy(§1.2). 초과는 색이 아니라 무게로 알린다(그린 외 단독 색 금지).
                    .foregroundStyle(body_.count > 500 ? .primary : .secondary)
                    .fontWeight(body_.count > 500 ? .semibold : .regular)
            }
            Button {
                send()
            } label: {
                Group {
                    if sending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 34, height: 34)
                            .background(GlassTokens.prominentTint, in: Circle())
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                canSend ? GlassTokens.prominentTint : Color.secondary.opacity(0.45),
                                in: Circle())
                    }
                }
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .disabled(!canSend || sending)
            .accessibilityLabel("노트 올리기")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.panelRadius))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .sensoryFeedback(.success, trigger: sentCount)
        // 빈 상태 CTA → 컴포저 열기(값 변화만, 첫 렌더의 0 은 통과시키지 않는다).
        .onChange(of: focusSignal) { _, newValue in
            if newValue > 0 { focused = true }
        }
    }

    private var canSend: Bool {
        !trimmed.isEmpty && body_.count <= 500
    }

    private func send() {
        guard !sending, canSend else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await publish(trimmed)
                sentCount += 1
                body_ = ""
                focused = false
            } catch {
                ToastCenter.shared.show(String(localized: "노트를 올리지 못했습니다"))
            }
        }
    }
}
