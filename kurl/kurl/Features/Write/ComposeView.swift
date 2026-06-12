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

    private enum Field: Hashable { case title }
    @FocusState private var focusedField: Field?

    /// 본문 캔버스(UIKit 직결)의 포커스·커서 제어 — TextEditor selection 바인딩의
    /// 한글 조합 깨짐을 피해 FocusState 대신 delegate 콜백으로 추적한다.
    @State private var editorController = MarkdownEditorController()
    @State private var editorFocused = false

    @State private var title = ""
    @State private var tagsText = ""
    @State private var excerpt = ""
    @State private var markdown = ""
    @State private var postId: Int64?
    @State private var status = "DRAFT"
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var lastSavedSignature: String?
    @State private var lastSavedAt: Date?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var createTask: Task<Int64, Error>?

    // 시리즈
    @State private var seriesList: [MySeries] = []
    @State private var seriesId: Int64?
    @State private var savedSeriesId: Int64?

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
        .sheet(
            isPresented: $showPublish,
            onDismiss: {
                // 시트 위 시트를 피한다 — 예약·미리보기는 발행 시트가 닫힌 뒤 이어서 띄운다.
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
            .font(.system(size: 26, weight: .bold))
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
                    .font(.system(size: 14))
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
            if busy {
                ProgressView()
            } else if let at = lastSavedAt {
                Text("저장됨 \(at.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
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
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(Palette.hairline)
                                }
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 13))
                                    Text("커버 추가")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            Palette.hairlineStrong,
                                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    sheetField("태그") {
                        TextField("태그 (쉼표로 구분)", text: $tagsText)
                            .font(.system(size: 14))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(
                                Palette.chipBg,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    sheetField("소개글") {
                        TextField(
                            "소개글 — 카드와 검색에 보이는 한 단락", text: $excerpt, axis: .vertical
                        )
                        .font(.system(size: 14))
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
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 12))
                                Text(
                                    seriesList.first(where: { $0.id == seriesId })?.title
                                        ?? String(localized: "시리즈 없음")
                                )
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(GlassTokens.prominentTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave || busy)

                    // 비활성엔 이유를 — 흐린 버튼만 보여주고 침묵하지 않는다.
                    if !canSave {
                        Text("제목과 본문을 채우면 발행할 수 있어요.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }

                    HStack(spacing: 18) {
                        Button {
                            previewNext = true
                            showPublish = false
                        } label: {
                            Label("미리보기", systemImage: "doc.text.magnifyingglass")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(Palette.link)
                        .disabled(postId == nil)

                        if status != "PUBLISHED" {
                            Button("예약 발행…") {
                                scheduleNext = true
                                showPublish = false
                            }
                            .font(.system(size: 13))
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
        }
        .presentationDetents([.medium, .large])
    }

    /// 시트 필드 한 단 — 작은 라벨 + 컨트롤.
    private func sheetField(
        _ label: LocalizedStringKey, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.heading)
            content()
        }
    }

    private var scheduleSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("선택한 시각에 자동으로 발행됩니다.")
                    .font(.system(size: 14))
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

    private var tags: [String] {
        tagsText.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var signature: String {
        [title, tagsText, excerpt, markdown, seriesId.map(String.init) ?? ""].joined(separator: "\u{1F}")
    }

    private func loadExisting() async {
        guard !loaded else { return }
        loaded = true
        seriesList = (try? await WriteAPI.mySeries()) ?? []
        guard let post = existing else { return }
        title = post.title
        tagsText = (post.tags ?? []).joined(separator: ", ")
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
            if publish { dismiss() }
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
        GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Action.allCases, id: \.self) { action in
                            Button {
                                perform(action)
                            } label: {
                                Image(systemName: action.icon)
                                    .font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 14, weight: .semibold))
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
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                if let date = revision.createdAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                            Spacer()
                            Button("복원") {
                                restore(revision)
                            }
                            .font(.system(size: 13, weight: .medium))
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
