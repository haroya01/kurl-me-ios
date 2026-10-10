//
//  ComposeChooserSheet.swift
//  kurl
//

import SwiftUI

enum ComposeChoice: Equatable {
    case note
    case newPost
    case draft(MyPost)
    case allDrafts
}

/// 내 글 목록의 마지막 응답 — 스튜디오가 이미 받은 초안으로 글쓰기 고르기가 곧바로 그려지게 한다.
/// 로그아웃하면 AuthStore 가 비운다(다른 계정의 초안이 보이지 않게).
@MainActor
enum MyPostsCache {
    static var posts: [MyPost]?
}

/// 탭바 가운데 '글쓰기' — 노트와 긴 글은 다른 물건이라 무엇을 쓸지 먼저 고르고, 다듬던 초안을 이어 쓴다.
struct ComposeChooserSheet: View {
    let onChoose: (ComposeChoice) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var posts = MyPostsCache.posts ?? []
    @State private var contentHeight: CGFloat = 220

    private var drafts: [MyPost] {
        posts.filter(\.isDraft).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                kindRow("노트", detail: "짧게, 바로 올리기", systemImage: "text.bubble") { onChoose(.note) }
                    .accessibilityIdentifier("compose.chooser.note")
                kindRow("긴 글", detail: "제목과 본문, 초안으로 다듬기", systemImage: "doc.text") { onChoose(.newPost) }
                    .accessibilityIdentifier("compose.chooser.post")
            }
            if !drafts.isEmpty {
                Section("이어 쓰기") {
                    ForEach(drafts.prefix(3)) { draft in
                        Button { onChoose(.draft(draft)) } label: { draftRow(draft) }
                            .accessibilityIdentifier("compose.chooser.draft.\(draft.id)")
                    }
                    if drafts.count > 3 {
                        Button("모두 보기") { onChoose(.allDrafts) }
                            .foregroundStyle(Palette.link)
                            .accessibilityIdentifier("compose.chooser.allDrafts")
                    }
                }
            }
        }
        .tint(.brand)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
            contentHeight = height
        }
        .presentationDetents([.height(contentHeight), .large])
        .presentationDragIndicator(.visible)
        .task { await refresh() }
    }

    private func kindRow(
        _ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    private func draftRow(_ draft: MyPost) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if draft.title.isEmpty {
                    Text("제목 없는 초안")
                } else {
                    Text(verbatim: draft.title)
                }
            }
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            if let date = draft.updatedAt {
                Text(date.relativeShort)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    private func refresh() async {
        guard let fresh = try? await WriteAPI.myPosts() else { return }
        MyPostsCache.posts = fresh
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { posts = fresh }
    }
}
