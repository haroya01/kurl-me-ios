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
    @Environment(\.openURL) private var openURL
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum Field: Hashable { case title, tags, excerpt, editor }
    @FocusState private var focusedField: Field?

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

    // 시트
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
            if !(verticalSizeClass == .compact && focusedField == .editor) {
                meta
                Hairline()
                    .padding(.horizontal, Metrics.gutter)
            }
            editor
        }
        .navigationTitle(existing == nil ? "새 글" : "편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await loadExisting() }
        .onChange(of: signature) { scheduleAutosave() }
        .onChange(of: coverItem) { uploadPickedCover() }
        .onDisappear {
            // 디바운스 창에 걸린 마지막 변경을 버리지 않는다 — 즉시 1회 저장.
            autosaveTask?.cancel()
            if canSave, signature != lastSavedSignature {
                Task { await save(publish: false) }
            }
        }
        .sheet(isPresented: $showSchedule) { scheduleSheet }
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

    // MARK: 메타 영역

    private var meta: some View {
        VStack(spacing: 8) {
            TextField("제목", text: $title)
                .font(.system(size: 24, weight: .bold))
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .tags }
            TextField("태그 (쉼표로 구분)", text: $tagsText)
                .font(.system(size: 13))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .tags)
                .submitLabel(.next)
                .onSubmit { focusedField = .excerpt }
            TextField("소개글 — 카드와 검색에 보이는 한 단락", text: $excerpt, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1...3)
                .focused($focusedField, equals: .excerpt)

            HStack(spacing: 10) {
                // 시리즈 지정 — 멤버십은 저장 시점에 PUT 으로 반영.
                Menu {
                    Button("시리즈 없음") { seriesId = nil }
                    ForEach(seriesList) { series in
                        Button(series.title) { seriesId = series.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 11))
                        Text(seriesList.first(where: { $0.id == seriesId })?.title ?? String(localized: "시리즈 없음"))
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(seriesId == nil ? Palette.secondary : Palette.link)
                }

                Spacer()

                // 커버 — 썸네일 또는 추가 버튼.
                PhotosPicker(selection: $coverItem, matching: .images) {
                    if uploadingCover {
                        ProgressView().controlSize(.small)
                    } else if let coverUrl, let url = URL(string: coverUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Palette.hairline)
                        }
                        .frame(width: 44, height: 33)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 11))
                            Text("커버")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var editor: some View {
        TextEditor(text: $markdown)
            .focused($focusedField, equals: .editor)
            .font(.system(size: 16, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, Metrics.gutter - 4)
            .padding(.top, 4)
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
                Button("발행") { Task { await save(publish: true) } }
                    .font(.body.weight(.semibold))
                    .tint(.brand)
                    .disabled(!canSave || busy)
            }
            Menu {
                Button {
                    openPreview()
                } label: {
                    Label("미리보기", systemImage: "safari")
                }
                .disabled(postId == nil)
                if status != "PUBLISHED" {
                    Button {
                        showSchedule = true
                    } label: {
                        Label("예약 발행…", systemImage: "calendar.badge.clock")
                    }
                    .disabled(postId == nil)
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
                openURL(url)
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
                let uploaded = try await WriteAPI.uploadCover(postId: id, jpegData: jpeg)
                try await WriteAPI.updateCover(postId: id, url: uploaded.url, key: uploaded.key)
                coverUrl = uploaded.url
                lastSavedAt = Date()
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
