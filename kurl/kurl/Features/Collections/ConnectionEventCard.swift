//
//  ConnectionEventCard.swift
//  kurl
//

import SwiftUI

/// 큐레이터 연결 한 장 — 일반 글 카드 문법으로 수렴한 미니멀 카드(≤3층, 장식 아이콘 0, 웹 #891 미러).
/// 연결된 것(글 제목·하이라이트 구절·노트 본문)이 주인공으로 본문에 직접(중첩 박스·아이콘 없음),
/// why 조용한 한 줄, 맥락은 메타 한 줄(아바타 + "@큐레이터가 [컬렉션]에 연결 · 날짜", 컬렉션=그린 링크).
/// 발견 표면(팔로우 큐레이터 흐름)과 비로그인 첫 피드의 공개 연결 인터리브가 이 하나를 공유한다.
struct ConnectionEventCard: View {
    let event: ConnectionEvent
    /// 비로그인 첫 피드에서도 이 카드가 흐른다 — 이때 컬렉션 링크는 인증 전용 상세(401)로
    /// 데려가면 막다른 길이라, 정식 로그인 시트로 돌린다(발견 표면은 이미 로그인 뒤라 안 뜬다).
    @State private var showLoginPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 주인공 — 연결된 것(일반 카드 제목과 같은 급). 중첩 박스·아이콘 없이 본문에 직접.
            // 하이라이트만 세로 그린 스파인 유지(칠한 구절은 콘텐츠라). 노트는 종이 위 그대로.
            MinimalConnectionHero(block: event.block)

            // why — 큐레이터의 한 줄(콘텐츠라 유지). 일반 카드 소개글 자리, 스파인 없이 조용히.
            if let why = event.why {
                Text(why)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 맥락 한 줄 — 일반 카드 작가 행과 같은 결. 아바타 + "@큐레이터가 [컬렉션]에 연결 · 날짜".
            // 장식 아이콘 0, 컬렉션은 그린 텍스트(알약 아님). 로케일 어순은 xcstrings 위치 인자로 지킨다.
            // 행 전체 탭 = 컬렉션(연결의 주 문); 로그인 뒤에만 상세로, 비로그인이면 로그인 시트로.
            metaLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .loginPrompt(isPresented: $showLoginPrompt, message: "큐레이터가 엮은 컬렉션 이어 보기")
    }

    @ViewBuilder
    private var metaLine: some View {
        if AuthStore.shared.isSignedIn {
            NavigationLink(value: CollectionRef(id: event.collectionId)) { metaRow }
                .buttonStyle(.plain)
        } else {
            Button { showLoginPrompt = true } label: { metaRow }
                .buttonStyle(.plain)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 7) {
            AvatarView(author: event.curator, size: 20)
            // 큐레이터·컬렉션 이름을 서식 있는 Text 조각으로 끼워 로케일 어순을 지킨다(웹 t.rich 대응):
            // 컬렉션=그린, 나머지=secondary. 날짜는 · 뒤 faint.
            metaText
                .typeScale(.meta)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .expandTapTarget(6)
    }

    /// "@큐레이터가 [컬렉션]에 연결 · 날짜" — 컬렉션만 그린으로 강조한 단일 Text. 길/컬렉션 어투 분리.
    private var metaText: Text {
        let curator = Text(event.curator.username).foregroundStyle(Palette.secondary)
        let collection = Text(event.collectionTitle).foregroundStyle(Palette.link)
        // xcstrings 위치 인자(%1$@ 큐레이터 · %2$@ 컬렉션)로 로케일별 어순 유지.
        let phrase: Text = event.collectionKind == .path
            ? Text("\(curator)가 \(collection) 길에 엮음")
            : Text("\(curator)가 \(collection)에 연결")
        var line = phrase.foregroundStyle(Palette.secondary)
        if let at = event.connectedAt {
            line = line
                + Text("  ·  ").foregroundStyle(Palette.faint)
                + Text(at.relativeShort).foregroundStyle(Palette.faint)
        }
        return line
    }
}

/// 연결 이벤트의 주인공 — 웹 #891 미러. 글=제목만(박스·아이콘 없이 본문에 직접), 하이라이트=그린
/// 스파인+칠한 구절, 노트=본문 그대로. 전부 일반 카드 제목 급이 주인공이고 장식 꼬리표는 없다.
private struct MinimalConnectionHero: View {
    let block: ConnectionBlock

    var body: some View {
        switch block {
        case let .post(title, _, username, slug, _):
            NavigationLink(value: Route.post(username: username, slug: slug)) {
                Text(title)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .highlight(quote, _, username, slug):
            // 하이라이트 = 칠한 구절이 주인공. 세로 그린 스파인만 남기고(콘텐츠라), 탭은 그 문장으로 딥링크.
            NavigationLink(value: Route.postFocusQuote(username: username, slug: slug, quote: quote)) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.accent)
                        .frame(width: 3)
                    Text(quote)
                        .typeScale(.title)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .note(body, noteId, username):
            if let noteId {
                NavigationLink(value: Route.note(id: noteId)) {
                    NoteBlockLabel(text: body, username: username, scale: .title)
                }
                .buttonStyle(.plain)
            } else {
                NoteBlockLabel(text: body, username: username, scale: .title)
            }
        }
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
