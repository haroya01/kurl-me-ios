//
//  FilteredNotificationsView.swift
//  kurl
//

import SwiftUI

/// 알림 거르기가 따로 둔 알림 — 보낸 사람별 묶음(마스토돈 걸러진 알림). 받으면 그 사람의 알림이 목록으로
/// 들어오고 앞으로도 오며, 버리면 모아 둔 알림이 지워진다. 알림 맨 위 줄과 이 화면이 나눠 쓴다.
@MainActor
@Observable
final class FilteredNotificationStore {
    static let shared = FilteredNotificationStore()

    private(set) var senders: [FilteredSender] = []
    private(set) var loaded = false
    private(set) var failed = false
    /// 받기가 성공할 때마다 오른다 — 알림 목록이 다시 읽어 들어온 알림을 보인다.
    private(set) var acceptedCount = 0

    func load() async {
        do {
            senders = try await NotificationPolicyAPI.filtered()
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }

    func reset() {
        senders = []
        loaded = false
    }

    func answer(_ sender: FilteredSender, accept: Bool) async {
        let index = senders.firstIndex(of: sender)
        withAnimation(.snappy(duration: 0.2)) { senders.removeAll { $0 == sender } }
        do {
            if accept {
                try await NotificationPolicyAPI.accept(sender)
                acceptedCount += 1
                ToastCenter.shared.show(String(localized: "\(sender.username)님의 알림을 받아요"))
            } else {
                try await NotificationPolicyAPI.dismiss(sender)
            }
        } catch {
            if let index {
                withAnimation(.snappy(duration: 0.2)) {
                    senders.insert(sender, at: min(index, senders.count))
                }
            }
            ToastCenter.shared.show(String(localized: "처리하지 못했어요"))
        }
    }
}

struct FilteredNotificationsView: View {
    @State private var store = FilteredNotificationStore.shared

    var body: some View {
        ReadingColumn(spacing: 0) {
            Color.clear.frame(height: 8)
            if !store.loaded {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if store.failed && store.senders.isEmpty {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await store.load() } })
                    .padding(.top, 60)
            } else if store.senders.isEmpty {
                ContentUnavailableView {
                    Text("걸러진 알림이 없어요")
                } description: {
                    Text("설정의 알림 거르기에서 어떤 알림을 따로 둘지 고를 수 있어요.")
                }
                .padding(.top, 60)
            } else {
                Text("알림 거르기가 따로 둔 알림이에요. 받으면 그 사람의 알림이 목록에 들어오고 앞으로도 와요.")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding(.vertical, 10)
                LazyVStack(spacing: 0) {
                    ForEach(store.senders) { sender in
                        row(sender)
                        if sender.id != store.senders.last?.id { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("걸러진 알림")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load() }
        .task { await store.load() }
    }

    private func row(_ sender: FilteredSender) -> some View {
        HStack(spacing: 12) {
            Group {
                if let route = sender.route {
                    NavigationLink(value: route) { person(sender) }
                        .buttonStyle(.plain)
                } else {
                    person(sender)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button("버리기") { Task { await store.answer(sender, accept: false) } }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("filtered.dismiss")
                Button("받기") { Task { await store.answer(sender, accept: true) } }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.accentFill)
                    .accessibilityIdentifier("filtered.accept")
            }
            .controlSize(.small)
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filtered.row.\(sender.username)")
    }

    private func person(_ sender: FilteredSender) -> some View {
        HStack(spacing: 12) {
            AvatarView(author: sender.asAuthor, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: sender.username)
                    .typeScale(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("알림 \(sender.count)개")
                    if let date = sender.lastAt {
                        Text(verbatim: "·")
                        Text(date.relativeShort)
                    }
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
