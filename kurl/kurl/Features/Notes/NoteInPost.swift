//
//  NoteInPost.swift
//  kurl
//

import SwiftUI

/// 이 서버가 주는 노트 주소 — 웹 kurlNoteId, 백엔드 PostNoteQuotes와 같은 규칙(경로 끝 /notes/{id}).
enum NoteURL {
    private static let hosts: Set<String> = Set(
        [Config.blogBase.host, Config.apiBase.host].compactMap { $0?.lowercased() })

    static func id(from raw: String) -> Int64? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              var host = url.host?.lowercased()
        else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        guard hosts.contains(host) else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[parts.count - 2] == "notes",
              parts[parts.count - 1].allSatisfy(\.isASCIIDigit)
        else { return nil }
        return Int64(parts[parts.count - 1])
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// 글에 실린 노트. 웹 독자는 노트를 익명으로 불러오므로, 누구나 볼 수 있는 노트만 카드로 —
/// 팔로워 공개·지워진 노트는 독자마다 다르게 보이지 않게 링크 카드로 둔다.
struct NoteEmbedCard<Fallback: View>: View {
    let noteId: Int64
    @ViewBuilder let fallback: () -> Fallback

    @State private var note: Note?
    @State private var failed = false

    var body: some View {
        Group {
            if let note {
                NavigationLink(value: Route.note(id: note.id)) {
                    QuotedNoteCard(note: QuotedNote(note), full: true)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .accessibilityIdentifier("post.noteEmbed.\(noteId)")
            } else if failed {
                fallback()
            } else {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(Palette.hairline)
                    .frame(height: 96)
                    .padding(.vertical, 6)
            }
        }
        .task(id: noteId) {
            guard note == nil else { return }
            do {
                let thread = try await NoteAPI.thread(id: noteId)
                if thread.note.noteVisibility.shareable {
                    note = thread.note
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}

/// 탭 스택 밖에서 여는 새 글 — 공유 메뉴의 "블로그 글로 인용"(노트 주소가 첫 줄, 발행된 글에서 노트 카드가 된다)과
/// 노트 작성기의 "긴 글로 쓰기"(쓰던 본문)가 쓴다.
struct PostComposerCover: View {
    let initialMarkdown: String
    var isDraft = false

    var body: some View {
        NavigationStack {
            ComposeView(
                post: nil, initialMarkdown: initialMarkdown.isEmpty ? nil : initialMarkdown,
                initialMarkdownIsDraft: isDraft, onSaved: {})
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}
