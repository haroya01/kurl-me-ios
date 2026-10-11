//
//  ComposeChooserSheet.swift
//  kurl
//

import SwiftUI

enum ComposeChoice: Equatable {
    case note
    case newPost
    case draft(MyPost)
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

    private enum Page: Hashable {
        case allDrafts
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var posts = MyPostsCache.posts ?? []
    @State private var contentHeight: CGFloat = 220
    @State private var path: [Page] = []

    private var drafts: [MyPost] {
        posts.filter(\.isDraft).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    kindRow("노트", systemImage: "text.bubble") { onChoose(.note) }
                        .accessibilityIdentifier("compose.chooser.note")
                    kindRow("긴 글", systemImage: "doc.text") { onChoose(.newPost) }
                        .accessibilityIdentifier("compose.chooser.post")
                }
                if !drafts.isEmpty {
                    Section {
                        ForEach(drafts.prefix(3)) { draft in
                            draftRow(draft)
                                .accessibilityIdentifier("compose.chooser.draft.\(draft.id)")
                        }
                    } header: {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("이어 쓰기")
                                Spacer()
                                showAllDrafts
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("이어 쓰기")
                                showAllDrafts
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.readingBg)
            .contentMargins(.top, 12, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
                contentHeight = height
            }
            .navigationDestination(for: Page.self) { _ in allDrafts }
        }
        .tint(.brand)
        .presentationDetents(path.isEmpty ? [.height(contentHeight), .large] : [.large])
        .presentationDragIndicator(.visible)
        .task { await refresh() }
    }

    @ViewBuilder private var showAllDrafts: some View {
        if drafts.count > 3 {
            Button("모두 보기") { path.append(.allDrafts) }
                .foregroundStyle(Palette.link)
                .accessibilityIdentifier("compose.chooser.allDrafts")
        }
    }

    private var allDrafts: some View {
        List(drafts) { draft in
            draftRow(draft)
                .accessibilityIdentifier("compose.chooser.allDrafts.\(draft.id)")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.readingBg)
        .navigationTitle(Text(LocalizedStringResource("heading.drafts", defaultValue: "임시저장")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func kindRow(
        _ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .foregroundStyle(Palette.ink)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    private func draftRow(_ draft: MyPost) -> some View {
        Button { onChoose(.draft(draft)) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if draft.title.isEmpty {
                            Text("제목 없음")
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
            } icon: {
                Image(systemName: "doc.text")
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
