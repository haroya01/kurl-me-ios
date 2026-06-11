//
//  ComposeView.swift
//  kurl
//

import SwiftUI

/// 마크다운 컴포즈 — 제목 한 줄 + 본문 전체가 캔버스인 몰입형. 저장 시 서버가 md→blocks
/// 변환을 수행하고 왕복 정규화된 마크다운을 돌려주므로, 편집 상태는 항상 canonical 형태.
/// 새 글은 첫 저장에서 초안을 만들고, 기존 글은 본문만 편집한다(제목·태그 등 메타데이터는 웹).
struct ComposeView: View {
    let existing: MyPost?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var markdown = ""
    @State private var postId: Int64?
    @State private var isDraft = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var loaded = false

    init(post: MyPost?, onSaved: @escaping () -> Void) {
        self.existing = post
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("제목", text: $title)
                .font(.system(size: 24, weight: .bold))
                .disabled(existing != nil)
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
        .navigationTitle(existing == nil ? "새 글" : "본문 편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if busy {
                    ProgressView()
                } else {
                    Button("저장") { Task { await save(publish: false) } }
                        .disabled(!canSave)
                    if isDraft {
                        Button("발행") { Task { await save(publish: true) } }
                            .font(.body.weight(.semibold))
                            .tint(.brand)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .task { await loadExisting() }
        .alert(
            "저장하지 못했습니다",
            isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadExisting() async {
        guard !loaded else { return }
        loaded = true
        guard let post = existing else { return }
        title = post.title
        postId = post.id
        isDraft = post.isDraft
        do {
            markdown = try await WriteAPI.markdown(postId: post.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(publish: Bool) async {
        guard !busy else { return }
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
            markdown = canonical
            if publish {
                _ = try await WriteAPI.publish(postId: id)
                isDraft = false
            }
            onSaved()
            if publish { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
