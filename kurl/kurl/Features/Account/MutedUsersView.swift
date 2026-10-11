//
//  MutedUsersView.swift
//  kurl
//

import SwiftUI

enum MuteDuration: Int, CaseIterable, Identifiable {
    case forever = 0
    case fiveMinutes = 300
    case thirtyMinutes = 1800
    case hour = 3600
    case sixHours = 21_600
    case day = 86_400
    case threeDays = 259_200
    case week = 604_800

    var id: Int { rawValue }

    var seconds: Int? { self == .forever ? nil : rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .forever: "무기한"
        case .fiveMinutes: "5분"
        case .thirtyMinutes: "30분"
        case .hour: "1시간"
        case .sixHours: "6시간"
        case .day: "1일"
        case .threeDays: "3일"
        case .week: "7일"
        }
    }
}

struct MuteSheet: View {
    let username: String
    let onMuted: (InteractionsAPI.MuteStatus) -> Void

    @State private var hidesNotifications = true
    @State private var duration: MuteDuration = .forever
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("알림도 숨기기", isOn: $hidesNotifications)
                        .accessibilityIdentifier("mute.notifications")
                    Picker("기간", selection: $duration) {
                        ForEach(MuteDuration.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("mute.duration")
                } footer: {
                    Text("\(username)님의 노트가 최신·팔로잉·리스트·답글에서 숨겨져요. 프로필에서는 그대로 보이고, 상대에게 알리지 않아요.")
                }
            }
            .navigationTitle("\(username)님 뮤트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await mute() }
                    } label: {
                        if saving { ProgressView() } else { Text("뮤트") }
                    }
                    .disabled(saving)
                    .accessibilityIdentifier("mute.confirm")
                }
            }
        }
        .presentationDetents([.height(340), .medium])
    }

    private func mute() async {
        saving = true
        defer { saving = false }
        do {
            let status = try await InteractionsAPI.mute(
                username: username, notifications: hidesNotifications, duration: duration.seconds)
            onMuted(status)
            ToastCenter.shared.show(String(localized: "뮤트했어요. 노트 피드에서 보이지 않아요"))
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "뮤트하지 못했어요"))
        }
    }
}

struct MutedUsersView: View {
    @State private var muted: [InteractionsAPI.MutedUser] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            Color.clear.frame(height: 8)
            if loading && muted.isEmpty {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed && muted.isEmpty {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await load() } })
                    .padding(.top, 60)
            } else if muted.isEmpty {
                ContentUnavailableView {
                    Text("뮤트한 사용자가 없어요").bold()
                } description: {
                    Text("작가 페이지의 ⋯ 메뉴에서 뮤트할 수 있어요.")
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(muted) { user in
                        row(user)
                        if user.id != muted.last?.id { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("뮤트한 사용자")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .task { await load() }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            muted = try await InteractionsAPI.listMuted()
        } catch {
            failed = true
        }
        loading = false
    }

    private func row(_ user: InteractionsAPI.MutedUser) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                author: Author(id: user.id, username: user.username, bio: nil, avatarUrl: user.avatarUrl),
                size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Group {
                    if let end = user.expiresAt {
                        Text("\(end, format: .dateTime.month().day().hour().minute())까지")
                    } else {
                        Text("무기한")
                    }
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            Button("뮤트 해제") {
                Task {
                    do {
                        try await InteractionsAPI.unmute(username: user.username)
                        withAnimation(.snappy(duration: 0.2)) { muted.removeAll { $0.id == user.id } }
                        ToastCenter.shared.show(String(localized: "뮤트를 해제했어요"))
                    } catch {
                        ToastCenter.shared.show(String(localized: "해제하지 못했어요"))
                    }
                }
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.link)
            .accessibilityIdentifier("muted.unmute.\(user.username)")
        }
        .padding(.vertical, 12)
    }
}
