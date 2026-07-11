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
        case .newPost: return "구독 작가의 새 글"
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
        case .newPost: return "구독한 작가가 새 글을 발행할 때"
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
        case .seriesSubscribe: return "square.stack"
        case .newPost: return "doc.text"
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
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("잠시 후 다시 시도해 주세요")
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                        .foregroundStyle(Palette.accent)
                }
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
