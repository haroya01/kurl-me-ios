//
//  NotificationPolicyView.swift
//  kurl
//

import SwiftUI

/// 설정 > 알림 거르기 — 마스토돈 알림 정책. 범주마다 받기·거르기·버리기를 고르고, 거른 알림은 알림 맨 위
/// "걸러진 알림"에 보낸 사람별로 모인다. 고르는 즉시 저장하고, 실패하면 그 줄만 되돌린다.
struct NotificationPolicyView: View {
    @State private var policy: NotificationPolicy?
    @State private var failed = false
    @State private var revertPulse = 0

    private struct Category: Identifiable {
        let id: WritableKeyPath<NotificationPolicy, NotificationPolicy.Level>
        let title: LocalizedStringKey
        let caption: LocalizedStringKey
    }

    private let categories: [Category] = [
        Category(
            id: \.forNotFollowing, title: "내가 팔로우하지 않는 사람",
            caption: "이 서버 회원과 다른 서버 계정 모두"),
        Category(
            id: \.forNotFollowers, title: "나를 팔로우하지 않는 사람",
            caption: "팔로우한 지 3일이 안 된 사람도 여기에 들어가요"),
        Category(
            id: \.forNewAccounts, title: "새 계정",
            caption: "만든 지 30일이 안 된 계정"),
        Category(
            id: \.forPrivateMentions, title: "요청하지 않은 개인 멘션",
            caption: "내가 팔로우하지 않는 사람이 나만 보이게 언급한 노트"),
    ]

    var body: some View {
        ReadingColumn(spacing: 0) {
            if let policy {
                RailHeading("이런 사람의 알림은")
                    .padding(.top, 24)
                    .padding(.bottom, 4)
                ForEach(categories) { category in
                    row(category, level: policy[keyPath: category.id])
                    if category.id != categories.last?.id { Hairline() }
                }
                Text("거른 알림은 알림 맨 위 \"걸러진 알림\"에 모여요. 받기로 고른 사람의 알림은 그 뒤로 늘 와요. 버린 알림은 남지 않아요. 내가 구독한 새 글·새 노트·투표 마감·수정 알림은 거르지 않아요.")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 12)
            } else if failed {
                ErrorState(
                    message: String(localized: "잠시 후 다시 시도해 주세요"),
                    retry: { Task { await load() } })
                    .padding(.top, 60)
            } else {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .navigationTitle("알림 거르기")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .task { await load() }
        .sensoryFeedback(.warning, trigger: revertPulse)
    }

    private func row(_ category: Category, level: NotificationPolicy.Level) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Text(category.caption)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Picker(
                category.title,
                selection: Binding(
                    get: { level },
                    set: { save(category.id, to: $0) })
            ) {
                ForEach(NotificationPolicy.Level.allCases, id: \.self) { option in
                    Text(Self.label(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Palette.accent)
            .accessibilityIdentifier("policy.\(Self.identifier(category.id))")
        }
        .padding(.vertical, 11)
    }

    static func label(_ level: NotificationPolicy.Level) -> LocalizedStringKey {
        switch level {
        case .accept: "받기"
        case .filter: "거르기"
        case .drop: "버리기"
        }
    }

    private static func identifier(_ path: WritableKeyPath<NotificationPolicy, NotificationPolicy.Level>) -> String {
        switch path {
        case \.forNotFollowing: "notFollowing"
        case \.forNotFollowers: "notFollowers"
        case \.forNewAccounts: "newAccounts"
        default: "privateMentions"
        }
    }

    private func load() async {
        do {
            policy = try await NotificationPolicyAPI.policy()
            failed = false
        } catch {
            failed = policy == nil
        }
    }

    private func save(
        _ path: WritableKeyPath<NotificationPolicy, NotificationPolicy.Level>, to level: NotificationPolicy.Level
    ) {
        guard var next = policy, next[keyPath: path] != level else { return }
        let previous = next
        next[keyPath: path] = level
        policy = next
        Task {
            do {
                policy = try await NotificationPolicyAPI.update(next)
            } catch {
                policy = previous
                revertPulse += 1
                ToastCenter.shared.show(String(localized: "설정을 저장하지 못했습니다"))
            }
        }
    }
}
