//
//  NotificationPreferencesView.swift
//  kurl
//

import SwiftUI

/// 화면 레이어의 라벨·설명·아이콘 — 계약(NotificationKind)과 분리(§API=Foundation only).
extension NotificationKind {
    /// 행 제목 — LocalizedStringKey(소스=ko, xcstrings 가 en/ja/vi/hi 로 번역).
    var title: LocalizedStringKey {
        switch self {
        case .like: return "좋아요"
        case .comment: return "댓글"
        case .reply: return "답글"
        case .mention: return "멘션"
        case .follow: return "팔로우"
        case .seriesSubscribe: return "시리즈 구독"
        case .newPost: return "팔로우한 작가의 새 글"
        case .connected: return "내 글이 컬렉션에 엮일 때"
        case .pathGrew: return "엮인 길에 새 글이 이어질 때"
        case .noteReply: return "내 노트 답글"
        case .noteQuote: return "내 노트 인용"
        case .noteMention: return "노트 멘션"
        case .noteLike: return "내 노트 좋아요"
        case .noteRepost: return "내 노트 리포스트"
        case .notePoll: return "투표 마감"
        case .notePost: return "종을 켠 사람의 새 노트"
        case .noteEdit: return "공유한 노트의 수정"
        case .remoteFollow: return "다른 서버의 팔로워"
        }
    }

    /// 한 줄 설명 — 무슨 일이 벌어졌을 때의 알림인지.
    var caption: LocalizedStringKey {
        switch self {
        case .like: return "누가 내 글을 좋아할 때"
        case .comment: return "누가 내 글에 댓글을 남길 때"
        case .reply: return "누가 내 댓글에 답글을 남길 때"
        case .mention: return "누가 나를 언급할 때"
        case .follow: return "누가 나를 팔로우할 때"
        case .seriesSubscribe: return "누가 내 시리즈를 구독할 때"
        case .newPost: return "팔로우한 작가가 새 글을 발행할 때"
        case .connected: return "누가 내 글·하이라이트를 컬렉션에 엮을 때"
        case .pathGrew: return "내가 엮인 길에 새 글이 이어질 때"
        case .noteReply: return "누가 내 노트에 답글을 남길 때"
        case .noteQuote: return "누가 내 노트를 인용할 때"
        case .noteMention: return "누가 노트에서 나를 언급할 때"
        case .noteLike: return "누가 내 노트를 좋아할 때. 다른 서버의 좋아요도 포함해요"
        case .noteRepost: return "누가 내 노트를 리포스트하거나 다른 서버에서 부스트할 때"
        case .notePoll: return "내 투표나 참여한 투표가 끝났을 때"
        case .notePost: return "작가 페이지에서 종을 켠 사람이 새 노트를 올릴 때"
        case .noteEdit: return "내가 리포스트하거나 인용한 노트를 작성자가 고칠 때"
        case .remoteFollow: return "마스토돈 같은 다른 서버 계정이 나를 팔로우할 때"
        }
    }

    /// 행 아이콘 — 종류의 성격을 한눈에(SF Symbols).
    var icon: String {
        switch self {
        case .like: return "heart"
        case .comment: return "bubble.left"
        case .reply: return "arrowshape.turn.up.left"
        case .mention: return "at"
        case .follow: return "person.badge.plus"
        case .seriesSubscribe: return "books.vertical"
        case .newPost: return "doc.text"
        case .connected: return "link"
        case .pathGrew: return "arrow.triangle.branch"
        case .noteReply: return "arrowshape.turn.up.left"
        case .noteQuote: return "quote.bubble"
        case .noteMention: return "at"
        case .noteLike: return "heart"
        case .noteRepost: return "arrow.2.squarepath"
        case .notePoll: return "chart.bar.xaxis"
        case .notePost: return "bell"
        case .noteEdit: return "pencil"
        case .remoteFollow: return "person.badge.plus"
        }
    }
}

/// 알림 종류별 켬/끔 — 벨에 무엇이 쌓일지 종류마다 끈다. 종이 세계(§1): 유리 없이
/// 행·구분선·타이포로만. 토글은 낙관적으로 즉시 반영하고 뒤에서 PUT, 실패하면 되돌린다.
struct NotificationPreferencesView: View {
    @State private var prefs: [NotificationKind: Bool] = [:]
    @State private var loading = true
    @State private var loadError: String?
    /// 저장 실패로 되돌린 순간의 햅틱 — 잘못된 성공을 몸으로도 알린다.
    @State private var revertPulse = 0

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if loadError != nil, prefs.isEmpty {
                ErrorState(
                    message: String(localized: "잠시 후 다시 시도해 주세요"),
                    retry: { Task { await load() } })
                    .padding(.top, 60)
            } else {
                RailHeading("알림 종류")
                    .padding(.top, 24)
                    .padding(.bottom, 4)
                ForEach(Array(NotificationKind.allCases.enumerated()), id: \.element) { index, kind in
                    row(kind)
                    if index < NotificationKind.allCases.count - 1 { Hairline() }
                }
                Text("끈 종류는 벨과 푸시에 오지 않아요")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 12)
                    .padding(.leading, 32)
            }
        }
        .navigationTitle("알림 종류")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        // 설정 스택의 하위 화면 — 밀고 들어와도 하단바 접힘을 유지한다(차단 목록과 같은 사연).
        .hidesTabBar()
        .task { await load() }
        .sensoryFeedback(.warning, trigger: revertPulse)
    }

    private func row(_ kind: NotificationKind) -> some View {
        Toggle(isOn: binding(for: kind)) {
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.accentMarker)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                    Text(kind.caption)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Palette.accent)
        .padding(.vertical, 11)
        .accessibilityHint(Text(kind.caption))
    }

    private func binding(for kind: NotificationKind) -> Binding<Bool> {
        Binding(
            get: { prefs[kind] ?? true },
            set: { newValue in save(kind, enabled: newValue) }
        )
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            prefs = try await NotificationPreferencesAPI.load()
            loadError = nil
        } catch {
            // 실패가 "전부 켜짐"으로 위장하지 않게 — 이미 받은 값이 있으면 보존한다.
            if prefs.isEmpty { loadError = error.localizedDescription }
        }
    }

    /// 낙관적으로 즉시 반영하고 뒤에서 확정. 실패하면 그 종류만 되돌리고 알린다(거짓 성공 금지).
    private func save(_ kind: NotificationKind, enabled: Bool) {
        let previous = prefs[kind] ?? true
        guard previous != enabled else { return }
        prefs[kind] = enabled
        Task {
            do {
                try await NotificationPreferencesAPI.update(kind, enabled: enabled)
            } catch {
                prefs[kind] = previous
                revertPulse += 1
                ToastCenter.shared.show(String(localized: "설정을 저장하지 못했습니다"))
            }
        }
    }
}
