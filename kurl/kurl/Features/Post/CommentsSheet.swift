//
//  CommentsSheet.swift
//  kurl
//

import SwiftUI

/// 발견 덱의 댓글 — 덱 페이지가 곧 열린 글이므로 대화만 시트 한 겹 아래로.
/// 글 상세의 댓글 부품(CommentRow/CommentComposer)을 그대로 쓰고, 비콘은 쏘지 않는다.
struct CommentsSheet: View {
    @State private var model: PostDetailViewModel
    @State private var replyTo: Comment?

    init(username: String, slug: String) {
        _model = State(initialValue: PostDetailViewModel(
            username: username, slug: slug, recordsView: false))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    switch model.phase {
                    case .idle, .loading:
                        ProgressView().tint(Palette.accent)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("다시 시도") { Task { await model.load() } }
                                .foregroundStyle(Palette.accent)
                        }
                        .padding(.top, 40)
                    case .loaded:
                        if model.comments.isEmpty {
                            Text("아직 댓글이 없습니다")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        }
                        ForEach(model.comments) { comment in
                            CommentRow(model: model, comment: comment, replyTo: $replyTo)
                                .padding(.leading, comment.parentId != nil ? 28 : 0)
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 16)
                .frame(maxWidth: Metrics.readingColumn)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if case .loaded = model.phase {
                    CommentComposer(model: model, replyTo: $replyTo)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                        .background(.bar)
                }
            }
            .onChange(of: model.comments) {
                // 답글 대상이 사라지면 답글 모드 해제 — 글 상세와 같은 가드.
                if let target = replyTo, !model.comments.contains(where: { $0.id == target.id }) {
                    replyTo = nil
                }
            }
            .navigationTitle("댓글 \(model.comments.count)")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
        }
    }
}
