//
//  ConnectionEventRow.swift
//  kurl
//

import SwiftUI

struct ConnectionEventRow: View {
    let event: ConnectionEvent
    /// 비로그인 첫 피드에서도 흐른다 — 컬렉션 상세는 인증 전용(401)이라 로그인 시트로 돌린다.
    @State private var showLoginPrompt = false

    var body: some View {
        Group {
            if let route {
                NavigationLink(value: route) { layout }
                    .buttonStyle(RowButtonStyle())
            } else {
                layout
            }
        }
        .loginPrompt(isPresented: $showLoginPrompt, message: "컬렉션을 열려면 로그인하세요")
        .accessibilityIdentifier("feed.connection.\(event.id)")
    }

    private var layout: some View {
        RowLayout(title: title, excerpt: excerpt, excerptIsBody: isNote) {
            context
        } byline: {
            if let author {
                AuthorByline(author: author)
            }
        }
    }

    private var route: Route? {
        switch event.block {
        case let .post(_, _, username, slug, _):
            .post(username: username, slug: slug)
        case let .highlight(quote, _, username, slug):
            .postFocusQuote(username: username, slug: slug, quote: quote)
        case let .note(_, noteId, _):
            noteId.map { .note(id: $0) }
        }
    }

    private var title: String? {
        switch event.block {
        case let .post(title, _, _, _, _): title
        case let .highlight(_, postTitle, _, _): postTitle
        case .note: nil
        }
    }

    private var excerpt: Text? {
        switch event.block {
        case let .post(_, excerpt, _, _, _):
            let line = [event.why, excerpt].compactMap { $0 }.first { !$0.isEmpty }
            return line.map { Text($0) }
        case let .highlight(quote, _, _, _):
            return Text(verbatim: "“\(quote)”")
        case let .note(body, _, _):
            return Text(body)
        }
    }

    private var isNote: Bool {
        if case .note = event.block { return true }
        return false
    }

    private var author: Author? {
        let username: String? = switch event.block {
        case let .post(_, _, username, _, _): username
        case let .highlight(_, _, username, _): username
        case let .note(_, _, username): username
        }
        guard let username, !username.isEmpty else { return nil }
        return Author(id: 0, username: username, bio: nil, avatarUrl: nil)
    }

    @ViewBuilder
    private var context: some View {
        if AuthStore.shared.isSignedIn {
            NavigationLink(value: CollectionRef(id: event.collectionId)) { contextLine }
                .buttonStyle(.plain)
        } else {
            Button { showLoginPrompt = true } label: { contextLine }
                .buttonStyle(.plain)
        }
    }

    private var contextLine: some View {
        contextText
            .typeScale(.meta)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .expandTapTarget(6)
    }

    private var contextText: Text {
        let curator = Text(event.curator.username).foregroundStyle(Palette.secondary)
        let collection = Text(event.collectionTitle).foregroundStyle(Palette.link)
        var line = Text("\(curator)가 \(collection)에 연결").foregroundStyle(Palette.secondary)
        if let at = event.connectedAt {
            line = line
                + Text(verbatim: "  ·  ").foregroundStyle(Palette.faint)
                + Text(at.relativeShort).foregroundStyle(Palette.faint)
        }
        return line
    }
}

/// 연결된 블록 — 일반 글 카드 문법으로 수렴한 미니멀 렌더(웹 #894 미러). 글·상세 "이어진 것"·
/// 컬렉션 상세·하이라이트 스레드가 이 하나를 공유하므로, 장식 꼬리표(타입 태그·문서/인용/노트
/// 아이콘)와 중첩 박스를 걷어 연결된 것 자체가 종이 위 주인공이 되게 한다. 종류 구분은 실루엣만:
/// 글=제목이 카드 제목 급 · 하이라이트=그린 좌측 스파인 + 구절(칠한 구절이 콘텐츠) · 노트=본문 그대로.
struct BlockPreview: View {
    let block: ConnectionBlock

    var body: some View {
        switch block {
        case let .post(title, excerpt, username, slug, _):
            // 글 = 제목이 주인공. 중첩 박스·보더·문서 아이콘·"글" 태그 제거하고 종이에 직접,
            // 소개글은 조용한 한 줄. (연결의 주인공은 연결된 글이지 카드 장식이 아니다.)
            NavigationLink(value: Route.post(username: username, slug: slug)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .highlight(quote, postTitle, username, slug):
            // 하이라이트 = 칠한 구절이 주인공. 그린 좌측 스파인만 남기고(구절이 콘텐츠) 인용 아이콘·
            // "하이라이트" 태그 제거. 탭 = 글의 *그 문장*으로 딥링크. 출처 제목은 조용한 한 줄.
            NavigationLink(value: Route.postFocusQuote(username: username, slug: slug, quote: quote)) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.accent)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quote)
                            .typeScale(.body)
                            .foregroundStyle(Palette.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(postTitle)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .note(body, noteId, username):
            if let noteId {
                NavigationLink(value: Route.note(id: noteId)) {
                    NoteBlockLabel(text: body, username: username, scale: .body)
                }
                .buttonStyle(.plain)
            } else {
                NoteBlockLabel(text: body, username: username, scale: .body)
            }
        }
    }
}

private struct NoteBlockLabel: View {
    let text: String
    let username: String?
    let scale: TypeRole

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let username {
                Text(username)
                    .typeScale(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
            Text(text)
                .typeScale(scale)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
