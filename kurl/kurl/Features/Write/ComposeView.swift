//
//  ComposeView.swift
//  kurl
//

import SwiftUI

/// 마크다운 컴포즈 — 제목·태그·소개글 메타 + 본문 캔버스. 웹 에디터처럼
/// **자동저장**(입력 멈춤 2초 후 dirty 시그니처 비교)이 기본이고 저장 버튼은 즉시 실행용.
/// 본문은 서버 md→blocks 변환(왕복 정규화 채택), 메타는 PATCH(부분 수정 — slug 는 안 보냄).
struct ComposeView: View {
    let existing: MyPost?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var tagsText = ""
    @State private var excerpt = ""
    @State private var markdown = ""
    @State private var postId: Int64?
    @State private var isDraft = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var lastSavedSignature: String?
    @State private var lastSavedAt: Date?
    @State private var autosaveTask: Task<Void, Never>?

    init(post: MyPost?, onSaved: @escaping () -> Void) {
        self.existing = post
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField("제목", text: $title)
                    .font(.system(size: 24, weight: .bold))
                TextField("태그 (쉼표로 구분)", text: $tagsText)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("소개글 — 카드와 검색에 보이는 한 단락", text: $excerpt, axis: .vertical)
                    .font(.system(size: 13))
                    .lineLimit(1...3)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Hairline()
                .padding(.horizontal, Metrics.gutter)

            TextEditor(text: $markdown)
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
        .navigationTitle(existing == nil ? "새 글" : "편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                if isDraft {
                    Button("발행") { Task { await save(publish: true) } }
                        .font(.body.weight(.semibold))
                        .tint(.brand)
                        .disabled(!canSave || busy)
                }
            }
        }
        .task { await loadExisting() }
        .onChange(of: signature) { scheduleAutosave() }
        .onDisappear { autosaveTask?.cancel() }
        .alert(
            "저장하지 못했습니다",
            isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
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

    /// dirty 판정용 시그니처 — 웹 에디터의 sig 비교와 같은 아이디어.
    private var signature: String {
        [title, tagsText, excerpt, markdown].joined(separator: "\u{1F}")
    }

    private func loadExisting() async {
        guard !loaded else { return }
        loaded = true
        guard let post = existing else { return }
        title = post.title
        tagsText = (post.tags ?? []).joined(separator: ", ")
        excerpt = post.excerpt ?? ""
        postId = post.id
        isDraft = post.isDraft
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
        do {
            let id: Int64
            if let postId {
                id = postId
            } else {
                let created = try await WriteAPI.createDraft(
                    title: title.trimmingCharacters(in: .whitespaces))
                postId = created.id
                id = created.id
            }
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
            if publish {
                _ = try await WriteAPI.publish(postId: id)
                isDraft = false
            }
            lastSavedSignature = signature
            lastSavedAt = Date()
            onSaved()
            if publish { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
