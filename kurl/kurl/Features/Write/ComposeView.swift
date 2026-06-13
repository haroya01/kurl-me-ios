//
//  ComposeView.swift
//  kurl
//

import PhotosUI
import SwiftUI

/// 마크다운 컴포즈 — 제목·태그·소개글·시리즈·커버 메타 + 본문 캔버스.
/// 자동저장(2초 디바운스·dirty 시그니처)이 기본이고, ⋯ 메뉴에 미리보기/예약 발행/리비전.
/// 본문은 서버 md→blocks 변환, 메타는 PATCH 부분 수정(slug 는 안 보냄 — 발행 후 frozen).
struct ComposeView: View {
    let existing: MyPost?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    private enum Field: Hashable { case title }
    @FocusState private var focusedField: Field?

    /// 본문 캔버스(UIKit 직결)의 포커스·커서 제어 — TextEditor selection 바인딩의
    /// 한글 조합 깨짐을 피해 FocusState 대신 delegate 콜백으로 추적한다.
    @State private var editorController = MarkdownEditorController()
    @State private var editorFocused = false

    @State private var title = ""
    @State private var tags: [String] = []
    @State private var tagDraft = ""
    @State private var excerpt = ""
    @State private var markdown = ""
    @State private var postId: Int64?
    @State private var status = "DRAFT"
    @State private var busy = false
    /// 발행·예약 성공의 보상 박자 — 트리거 전용 카운터.
    @State private var publishCelebration = 0
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var lastSavedSignature: String?
    @State private var lastSavedAt: Date?
    @State private var showSaveStatus = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var createTask: Task<Int64, Error>?

    // 시리즈
    @State private var seriesList: [MySeries] = []
    @State private var seriesId: Int64?
    @State private var savedSeriesId: Int64?
    @State private var showNewSeries = false
    @State private var newSeriesTitle = ""
    @State private var creatingSeries = false

    // 커버
    @State private var coverUrl: String?
    @State private var coverItem: PhotosPickerItem?
    @State private var uploadingCover = false

    // 본문 이미지 — 스니펫 바의 사진 버튼이 연다. 업로드 후 커서 자리에 마크다운 삽입.
    @State private var showBodyImagePicker = false
    @State private var bodyImageItem: PhotosPickerItem?
    @State private var uploadingBodyImage = false

    // 시트
    @State private var showPublish = false
    @State private var scheduleNext = false
    @State private var previewNext = false
    @State private var previewItem: PreviewItem?

    struct PreviewItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    @State private var showSchedule = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var scheduleError: String?
    @State private var showRevisions = false

    init(post: MyPost?, onSaved: @escaping () -> Void) {
        self.existing = post
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            // 가로(compact 높이)에서 에디터에 포커스가 가면 메타를 접는다 —
            // 안 그러면 키보드+메타가 에디터 가시 영역을 0 으로 만든다.
            if !(verticalSizeClass == .compact && editorFocused) {
                meta
                Hairline()
                    .padding(.horizontal, Metrics.gutter)
            }
            editor
        }
        .background(Palette.readingBg.ignoresSafeArea())
        // 키보드 위에 뜨는 유리 마크다운 바 — 캔버스는 종이, 크롬은 유리(AGENTS.md §1).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editorFocused {
                MarkdownSnippetBar(perform: applySnippet) { editorController.dismissKeyboard() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: editorFocused)
        .navigationTitle(existing == nil ? "새 글" : "편집")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        // 쓰는 동안 탭 5개가 떠 있을 이유가 없다 — 에디터는 풀스크린 몰입.
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: publishCelebration)
        .toolbar { toolbarContent }
        .task {
            await loadExisting()
            // `--focus editor` / `--sheet publish` — 검증 진입로(simctl 터치 불가 우회).
            if Config.consumeLaunchValue(after: "--focus") == "editor" {
                // representable 의 makeUIView 가 붙은 뒤에 포커스를 줘야 한다.
                try? await Task.sleep(for: .milliseconds(200))
                editorController.focus()
            }
            if Config.consumeLaunchValue(after: "--sheet") == "publish" {
                showPublish = true
            }
        }
        .onChange(of: signature) { scheduleAutosave() }
        .onChange(of: coverItem) { uploadPickedCover() }
        .photosPicker(isPresented: $showBodyImagePicker, selection: $bodyImageItem, matching: .images)
        .onChange(of: bodyImageItem) { uploadBodyImage() }
        .onDisappear {
            // 디바운스 창에 걸린 마지막 변경을 버리지 않는다 — 즉시 1회 저장.
            autosaveTask?.cancel()
            if canSave, signature != lastSavedSignature {
                Task { await save(publish: false) }
            }
        }
        // 발행 준비 = 바텀 시트가 아니라 전체 화면 폼 — 짧은 시트에서 폼이 잘리고 하단
        // 버튼에 눌려 답답했다. 풀스크린이라 필드가 여유 있게 선다.
        .fullScreenCover(
            isPresented: $showPublish,
            onDismiss: {
                // 화면 위 시트를 피한다 — 예약·미리보기는 발행 폼이 닫힌 뒤 이어서 띄운다.
                if scheduleNext {
                    scheduleNext = false
                    showSchedule = true
                } else if previewNext {
                    previewNext = false
                    openPreview()
                }
            }
        ) { publishSheet }
        .sheet(isPresented: $showSchedule) { scheduleSheet }
        .sheet(item: $previewItem) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showRevisions) {
            RevisionsSheet(postId: postId) { restored in
                markdown = restored
                lastSavedSignature = signature
            }
        }
        .alert(
            "저장하지 못했습니다",
            isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: 메타 영역 — 캔버스엔 제목뿐. 태그·소개글·시리즈·커버는 발행 시트의 일.

    private var meta: some View {
        TextField("제목", text: $title)
            .font(.system(size: titleSize, weight: .bold))
            .focused($focusedField, equals: .title)
            .submitLabel(.next)
            .onSubmit { editorController.focus() }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, 12)
    }

    private var editor: some View {
        MarkdownTextView(text: $markdown, controller: editorController) { focused in
            editorFocused = focused
        }
        .padding(.horizontal, Metrics.gutter - 4)
        .overlay(alignment: .topLeading) {
            if markdown.isEmpty {
                Text("마크다운으로 쓰세요 — #, >, -, ```, 이미지·URL 한 줄이면 카드가 됩니다.")
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // 저장 상태는 평소엔 조용한 체크 아이콘 하나 — 탭하면 마지막 저장 시각을 팝오버로.
            // (항상 떠 있던 "저장됨 오후 X:XX" 텍스트가 중요도에 비해 과했다.)
            if busy {
                ProgressView().controlSize(.small)
            } else if let at = lastSavedAt {
                Button {
                    showSaveStatus = true
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15 * metaUnit))
                        .foregroundStyle(Palette.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("저장 상태 보기"))
                .popover(isPresented: $showSaveStatus) {
                    Text("저장됨 \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 13 * metaUnit))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("저장") { Task { await save(publish: false) } }
                .disabled(!canSave || busy)
            if status != "PUBLISHED" {
                // 발행 = 즉시 쏘지 않는다 — 발행 시트에서 메타데이터를 갖추는 마지막 한 박자.
                Button("발행") { showPublish = true }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(GlassTokens.prominentTint)
                    .disabled(!canSave || busy)
            }
        }
        // ⋯ 는 별도 유리 핀으로 — 저장·발행 묶음과 부가 동작을 물리적으로 분리.
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    openPreview()
                } label: {
                    Label("미리보기", systemImage: "safari")
                }
                .disabled(postId == nil)
                if status == "PUBLISHED" {
                    // 발행된 글의 태그·소개글·시리즈·커버 편집 — 같은 시트, 저장 모드.
                    Button {
                        showPublish = true
                    } label: {
                        Label("글 정보…", systemImage: "info.circle")
                    }
                }
                Button {
                    showRevisions = true
                } label: {
                    Label("리비전…", systemImage: "clock.arrow.circlepath")
                }
                .disabled(postId == nil)
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("더 보기")
        }
    }

    /// 발행 준비 — 캔버스에서 걷어낸 메타데이터(태그·소개글·시리즈·커버)가 모이는 자리.
    /// 미발행 글은 [지금 발행]이 주행동, 발행된 글은 같은 시트가 "글 정보" 저장 모드로 선다.
    private var publishSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sheetField("커버") {
                        PhotosPicker(selection: $coverItem, matching: .images) {
                            if uploadingCover {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(height: 64)
                            } else if let coverUrl, let url = URL(string: coverUrl) {
                                // 커버 히어로 — 카드/상세에 실릴 그 비율(16:9) 그대로. 탭하면 변경.
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(Palette.hairline)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 188)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 11 * metaUnit, weight: .semibold))
                                        Text("변경")
                                            .font(.system(size: 12 * metaUnit, weight: .medium))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.45), in: Capsule())
                                    .padding(10)
                                }
                            } else {
                                // 흐린 점선 + 가운데 텍스트가 "안 불러와진" 것처럼 보였다 —
                                // 채워진 타일 + 또렷한 심볼로 누를 자리를 분명히 한다.
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 26 * unit, weight: .regular))
                                    Text("커버 이미지 추가")
                                        .font(.system(size: 14 * unit, weight: .medium))
                                }
                                .foregroundStyle(Palette.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 150)
                                .background(
                                    Palette.chipBg,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    sheetField("태그") {
                        TagsField(tags: $tags, draft: $tagDraft)
                    }

                    sheetField("소개글") {
                        TextField(
                            "소개글 — 카드와 검색에 보이는 한 단락", text: $excerpt, axis: .vertical
                        )
                        .font(.system(size: 14 * unit))
                        .lineLimit(2...4)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(
                            Palette.chipBg,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    sheetField("시리즈") {
                        Menu {
                            Button("시리즈 없음") { seriesId = nil }
                            ForEach(seriesList) { series in
                                Button(series.title) { seriesId = series.id }
                            }
                            Divider()
                            Button {
                                newSeriesTitle = ""
                                showNewSeries = true
                            } label: {
                                Label("새 시리즈 만들기…", systemImage: "plus")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 12 * metaUnit))
                                Text(
                                    seriesList.first(where: { $0.id == seriesId })?.title
                                        ?? String(localized: "시리즈 없음")
                                )
                                .font(.system(size: 14 * unit, weight: .medium))
                                .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10 * metaUnit))
                            }
                            .foregroundStyle(
                                seriesId == nil
                                    ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.link))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Capsule())
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }

                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            // 주행동은 detent 높이와 무관하게 항상 보이게 — 시트 하단 고정.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        showPublish = false
                        Task { await save(publish: status != "PUBLISHED") }
                    } label: {
                        Text(status != "PUBLISHED" ? "지금 발행" : "저장")
                            .font(.system(size: 15 * unit, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(GlassTokens.prominentTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled((status != "PUBLISHED" ? !canPublish : !canSave) || busy)

                    // 비활성엔 이유를 — 흐린 버튼만 보여주고 침묵하지 않는다.
                    if let reason = publishBlockReason {
                        Text(reason)
                            .font(.system(size: 12 * metaUnit))
                            .foregroundStyle(Palette.secondary)
                    }

                    HStack(spacing: 18) {
                        Button {
                            previewNext = true
                            showPublish = false
                        } label: {
                            Label("미리보기", systemImage: "doc.text.magnifyingglass")
                                .font(.system(size: 13 * unit))
                        }
                        .foregroundStyle(Palette.link)
                        .disabled(postId == nil)

                        if status != "PUBLISHED" {
                            Button("예약 발행…") {
                                scheduleNext = true
                                showPublish = false
                            }
                            .font(.system(size: 13 * unit))
                            .foregroundStyle(Palette.link)
                            .disabled(postId == nil)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .navigationTitle(status != "PUBLISHED" ? "발행 준비" : "글 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { showPublish = false }
                }
            }
            .alert("새 시리즈", isPresented: $showNewSeries) {
                TextField("시리즈 제목", text: $newSeriesTitle)
                    .textInputAutocapitalization(.never)
                Button("만들기") { createNewSeries() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 글이 들어갈 새 시리즈를 만듭니다. 제목은 나중에 시리즈에서 바꿀 수 있어요.")
            }
        }
    }

    /// 시트 필드 한 단 — 작은 라벨 + 컨트롤.
    private func sheetField(
        _ label: LocalizedStringKey, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13 * unit, weight: .semibold))
                .foregroundStyle(Palette.heading)
            content()
        }
    }

    private var scheduleSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("선택한 시각에 자동으로 발행됩니다.")
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.secondary)
                DatePicker("발행 시각", selection: $scheduleDate, in: Date()...)
                    .datePickerStyle(.graphical)
                Spacer()
            }
            .padding(Metrics.gutter)
            .alert(
                "예약하지 못했습니다",
                isPresented: .init(get: { scheduleError != nil }, set: { if !$0 { scheduleError = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(scheduleError ?? "")
            }
            .navigationTitle("예약 발행")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showSchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("예약") { Task { await scheduleNow() } }
                        .disabled(busy)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: 상태

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 발행은 대표 태그(첫 태그) 1개가 필수 — 초안 저장(canSave)과는 분리한다.
    private var canPublish: Bool { canSave && !tags.isEmpty }

    /// 발행 버튼이 흐릴 때의 이유 한 줄 — 침묵하지 않는다.
    private var publishBlockReason: String? {
        if !canSave { return String(localized: "제목과 본문을 채우면 발행할 수 있어요.") }
        if status != "PUBLISHED", tags.isEmpty {
            return String(localized: "대표 태그를 1개 이상 정하면 발행할 수 있어요.")
        }
        return nil
    }

    private var signature: String {
        [title, tags.joined(separator: ","), excerpt, markdown, seriesId.map(String.init) ?? ""]
            .joined(separator: "\u{1F}")
    }

    private func loadExisting() async {
        guard !loaded else { return }
        loaded = true
        seriesList = (try? await WriteAPI.mySeries()) ?? []
        guard let post = existing else { return }
        title = post.title
        tags = post.tags ?? []
        excerpt = post.excerpt ?? ""
        coverUrl = post.ogImageUrl
        seriesId = post.seriesId
        savedSeriesId = post.seriesId
        postId = post.id
        status = post.status
        do {
            markdown = try await WriteAPI.markdown(postId: post.id)
            lastSavedSignature = signature
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 저장

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard canSave, signature != lastSavedSignature else { return }
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await save(publish: false)
        }
    }

    private func save(publish: Bool) async {
        guard !busy, canSave else { return }
        guard publish || signature != lastSavedSignature else { return }
        busy = true
        defer { busy = false }
        // 비행 중 타이핑이 "저장된 셈" 되지 않게 — 전송 시점 스냅샷을 기록한다.
        let snapshot = signature
        do {
            let id = try await ensurePost()
            let canonical = try await WriteAPI.replaceMarkdown(postId: id, markdown: markdown)
            // 사용자가 그 사이 더 입력했으면 정규화 본문으로 덮지 않는다(타이핑 손실 방지).
            if markdown == canonical || signature == lastSavedSignature {
                markdown = canonical
            }
            try await WriteAPI.updateMetadata(
                postId: id,
                title: title.trimmingCharacters(in: .whitespaces),
                excerpt: excerpt,
                tags: tags
            )
            if seriesId != savedSeriesId {
                try await WriteAPI.assign(postId: id, from: savedSeriesId, to: seriesId)
                savedSeriesId = seriesId
            }
            if publish {
                let published = try await WriteAPI.publish(postId: id)
                status = published.status
            }
            lastSavedSignature = snapshot
            lastSavedAt = Date()
            onSaved()
            // 스냅샷 이후 입력이 있었으면 디바운스를 다시 무장한다.
            if signature != snapshot { scheduleAutosave() }
            if publish {
                // 이 앱 최대의 순간이 무음으로 끝나면 안 된다 — 성공 햅틱 + 토스트 한 번.
                publishCelebration += 1
                ToastCenter.shared.show(String(localized: "발행되었습니다"))
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 단일 비행 — 자동저장과 커버 업로드가 동시에 들어와도 초안은 하나만 만든다.
    private func ensurePost() async throws -> Int64 {
        if let postId { return postId }
        if let running = createTask {
            return try await running.value
        }
        let task = Task<Int64, Error> {
            let created = try await WriteAPI.createDraft(
                title: title.trimmingCharacters(in: .whitespaces))
            return created.id
        }
        createTask = task
        defer { createTask = nil }
        let id = try await task.value
        postId = id
        return id
    }

    // MARK: 부가 동작

    private func openPreview() {
        guard let postId else { return }
        let slug = existing?.slug
        Task {
            // 새 글이면 목록에서 slug 를 다시 찾는다(생성 응답을 보관 안 했을 때 대비).
            let resolved: String
            if let slug {
                resolved = slug
            } else {
                resolved = (try? await WriteAPI.myPosts())?
                    .first(where: { $0.id == postId })?.slug ?? ""
            }
            if let url = try? await WriteAPI.previewURL(slug: resolved, postId: postId) {
                // 외부 사파리로 내쫓지 않는다 — 발행 전 확인은 인앱 시트로.
                previewItem = PreviewItem(url: url)
            }
        }
    }

    private func scheduleNow() async {
        guard let postId, !busy else { return }
        // 저장이 자체 busy 를 관리하므로 먼저 끝낸다 — busy 선점은 저장 스킵을 만든다.
        await save(publish: false)
        guard signature == lastSavedSignature else {
            scheduleError = errorMessage ?? String(localized: "저장하지 못했습니다")
            return
        }
        busy = true
        defer { busy = false }
        do {
            let scheduled = try await WriteAPI.schedule(postId: postId, at: scheduleDate)
            status = scheduled.status
            showSchedule = false
            onSaved()
            publishCelebration += 1
            ToastCenter.shared.show(String(localized: "예약되었습니다"))
            dismiss()
        } catch {
            // 시트가 떠 있는 동안 본체 알럿은 가려진다 — 시트 안에서 보여준다.
            scheduleError = error.localizedDescription
        }
    }

    private func uploadPickedCover() {
        guard let item = coverItem, !uploadingCover else { return }
        uploadingCover = true
        Task {
            defer { uploadingCover = false }
            do {
                let id = try await ensurePost()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.88)
                else { return }
                let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                try await WriteAPI.updateCover(postId: id, url: uploaded.url, key: uploaded.key)
                coverUrl = uploaded.url
                lastSavedAt = Date()
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: 새 시리즈

    /// 발행 폼에서 새 시리즈를 만들고 곧장 이 글에 지정한다. slug 는 제목에서 파생.
    private func createNewSeries() {
        let title = newSeriesTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !creatingSeries else { return }
        creatingSeries = true
        Task {
            defer { creatingSeries = false }
            do {
                let slug = makeSeriesSlug(from: title)
                let list = try await WriteAPI.createSeries(slug: slug, title: title)
                seriesList = list
                seriesId = (list.first { $0.slug == slug } ?? list.first { $0.title == title })?.id
                newSeriesTitle = ""
            } catch {
                ToastCenter.shared.show(String(localized: "시리즈를 만들지 못했습니다"))
            }
        }
    }

    /// 제목 → 유저별 유니크 slug. ASCII 영숫자만 남기고(한글은 떨궈) 짧은 토큰을 붙여 충돌 회피.
    private func makeSeriesSlug(from title: String) -> String {
        let mapped = title.lowercased().unicodeScalars.map {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) ? Character($0) : "-"
        }
        var base = String(mapped)
        while base.contains("--") { base = base.replacingOccurrences(of: "--", with: "-") }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.count < 2 { base = "series" }
        let token = String(Int.random(in: 1_000_000...9_999_999), radix: 36)
        return "\(base.prefix(40))-\(token)"
    }

    // MARK: 마크다운 스니펫 삽입 — 커서/선택 기준

    private func applySnippet(_ action: MarkdownSnippetBar.Action) {
        switch action {
        case .heading: editorController.applyLinePrefix("# ")
        case .quote: editorController.applyLinePrefix("> ")
        case .list: editorController.applyLinePrefix("- ")
        case .bold: editorController.wrapSelection("**")
        case .inlineCode: editorController.wrapSelection("`")
        case .codeBlock: editorController.insertFence()
        case .link: editorController.insertLink()
        case .image: showBodyImagePicker = true
        }
        // 프로그램 삽입은 delegate 를 거치지 않는다 — 바인딩(자동저장 시그니처) 수동 동기화.
        if action != .image {
            markdown = editorController.currentText
        }
    }

    /// 본문 이미지 — 골라서 업로드되면 커서 자리에 `![](url)` 한 줄로 들어간다.
    private func uploadBodyImage() {
        guard let item = bodyImageItem, !uploadingBodyImage else { return }
        uploadingBodyImage = true
        bodyImageItem = nil
        ToastCenter.shared.show(String(localized: "이미지 올리는 중…"))
        Task {
            defer { uploadingBodyImage = false }
            do {
                let id = try await ensurePost()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.88)
                else { return }
                let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                editorController.insertImageMarkdown(url: uploaded.url)
                markdown = editorController.currentText
                // 커버가 비어 있으면 본문 첫 이미지를 기본 커버로 — 이미지 있는 글이
                // 커버 없이 발행되지 않게(작성자는 발행 폼에서 언제든 바꿀 수 있다).
                if coverUrl == nil {
                    coverUrl = uploaded.url
                    try? await WriteAPI.updateCover(postId: id, url: uploaded.url, key: uploaded.key)
                    lastSavedAt = Date()
                    onSaved()
                }
            } catch {
                ToastCenter.shared.show(String(localized: "이미지를 올리지 못했습니다"))
            }
        }
    }
}

/// 키보드 위에 뜨는 유리 마크다운 바 — 에디터의 유일한 유리 크롬.
/// 표준 md 만 — 비표준 문법 버튼은 두지 않는다(웹 에디터와 같은 경계).
/// 좁은 화면에선 스니펫 캡슐이 가로 스크롤되고 터치 타깃 44pt 는 줄이지 않는다.
private struct MarkdownSnippetBar: View {
    let perform: (Action) -> Void
    let dismiss: () -> Void

    /// 아이콘만 키운다 — 44pt 터치 타깃 프레임은 작은 글자 설정에서도 줄이지 않는다.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    enum Action: CaseIterable {
        case heading, bold, inlineCode, codeBlock, quote, list, link, image

        var icon: String {
            switch self {
            case .heading: "number"
            case .bold: "bold"
            case .inlineCode: "chevron.left.forwardslash.chevron.right"
            case .codeBlock: "curlybraces"
            case .quote: "text.quote"
            case .list: "list.bullet"
            case .link: "link"
            case .image: "photo"
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .heading: "제목"
            case .bold: "굵게"
            case .inlineCode: "인라인 코드"
            case .codeBlock: "코드 블록"
            case .quote: "인용"
            case .list: "리스트"
            case .link: "링크"
            case .image: "이미지"
            }
        }
    }

    var body: some View {
        // 도구 캡슐과 키보드 내리기 버튼은 성격이 다른 컨트롤 — clusterSpacing(18) 안에서
        // 액체처럼 녹아 붙어(metaball) 한 덩어리로 보였다. 이 묶음의 융합 거리만 0 으로
        // (닿을 때만 융합) 두고 간격을 벌려 또렷한 두 컨트롤로 분리한다.
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Action.allCases, id: \.self) { action in
                            Button {
                                perform(action)
                            } label: {
                                Image(systemName: action.icon)
                                    .font(.system(size: 15 * unit, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(action.label))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button(action: dismiss) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14 * unit, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("키보드 내리기"))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

/// 리비전 목록 + 복원 — 복원하면 서버 상태가 바뀌므로 본문을 다시 읽어 에디터에 반영한다.
private struct RevisionsSheet: View {
    let postId: Int64?
    let onRestored: (String) -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    @State private var revisions: [PostRevision] = []
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if revisions.isEmpty {
                    ContentUnavailableView("리비전이 없습니다", systemImage: "clock.arrow.circlepath")
                } else {
                    List(revisions) { revision in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("v\(revision.versionNumber) — \(revision.titleSnapshot)")
                                    .font(.system(size: 15 * unit, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                if let date = revision.createdAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12 * metaUnit))
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                            Spacer()
                            Button("복원") {
                                restore(revision)
                            }
                            .font(.system(size: 13 * unit, weight: .medium))
                            .foregroundStyle(Palette.link)
                            .disabled(busy)
                        }
                        .listRowSeparatorTint(Palette.hairline)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("리비전")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if let postId {
                revisions = (try? await WriteAPI.revisions(postId: postId)) ?? []
            }
            loading = false
        }
    }

    private func restore(_ revision: PostRevision) {
        guard let postId, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await WriteAPI.restoreRevision(postId: postId, version: revision.versionNumber)
                let restored = try await WriteAPI.markdown(postId: postId)
                onRestored(restored)
                dismiss()
            } catch {
                // 복원 실패 — 시트는 열어두고 버튼만 다시 살린다.
            }
        }
    }
}

/// 대표 태그 칩 에디터 — 입력해서 칩으로 쌓고, 첫 칩이 "대표"(카드·글 위 카테고리).
/// 비대표 칩을 탭하면 대표로 끌어올리고, ✕ 로 지운다. 발행은 대표 1개가 필수.
private struct TagsField: View {
    @Binding var tags: [String]
    @Binding var draft: String
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("태그 입력 후 추가 (쉼표로 여러 개)", text: $draft)
                    .font(.system(size: 14 * unit))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .onChange(of: draft) { _, value in
                        if value.contains(",") { commit() } // 쉼표 입력 즉시 칩으로.
                    }
                Button { commit() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20 * unit))
                        .foregroundStyle(isDraftEmpty ? Palette.faint : Palette.accent)
                }
                .buttonStyle(.plain)
                .disabled(isDraftEmpty)
                .accessibilityLabel(Text("태그 추가"))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if tags.isEmpty {
                Text("첫 번째 태그가 대표 — 카드·글 위에 카테고리로 보입니다. (발행 시 1개 필수)")
                    .font(.system(size: 12 * metaUnit))
                    .foregroundStyle(Palette.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                        chip(tag, isPrimary: index == 0)
                    }
                }
                Text("탭하면 대표로 · ✕ 로 삭제")
                    .font(.system(size: 11 * metaUnit))
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private func chip(_ tag: String, isPrimary: Bool) -> some View {
        HStack(spacing: 5) {
            if isPrimary {
                Text("대표")
                    .font(.system(size: 10 * metaUnit, weight: .bold))
                    .opacity(0.9)
            }
            Button {
                promote(tag)
            } label: {
                Text(tag).font(.system(size: 13 * unit, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(isPrimary)
            .accessibilityLabel(Text(isPrimary ? "대표 태그 \(tag)" : "\(tag) — 대표로 지정"))

            Button {
                tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9 * metaUnit, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(tag) 삭제"))
        }
        .foregroundStyle(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.chipText))
        .padding(.leading, isPrimary ? 9 : 11)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            isPrimary ? AnyShapeStyle(Palette.accentFill) : AnyShapeStyle(Palette.chipBg),
            in: Capsule())
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commit() {
        let parts = draft
            .split(whereSeparator: { $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for part in parts where !tags.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
            tags.append(part)
        }
        draft = ""
    }

    private func promote(_ tag: String) {
        guard let index = tags.firstIndex(of: tag), index != 0 else { return }
        tags.remove(at: index)
        tags.insert(tag, at: 0)
    }
}

/// 칩이 줄을 넘기면 다음 줄로 흐르는 단순 flow 레이아웃(iOS 16+ Layout).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
