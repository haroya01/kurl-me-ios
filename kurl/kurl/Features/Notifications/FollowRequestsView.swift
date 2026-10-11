//
//  FollowRequestsView.swift
//  kurl
//

import SwiftUI

/// 기다리는 팔로우 요청 — 알림 맨 위 줄, 요청 화면, 요청 알림의 버튼이 한 목록을 나눠 쓴다.
/// 어디서 승인하든 다른 자리에서도 바로 빠진다.
@MainActor
@Observable
final class FollowRequestStore {
    static let shared = FollowRequestStore()

    private(set) var requests: [FollowRequest] = []
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var approvedCount = 0

    func load() async {
        do {
            requests = try await FollowRequestsAPI.pending()
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }

    func reset() {
        requests = []
        loaded = false
    }

    /// 낙관적으로 빼고, 실패하면 제자리에 되돌린다.
    func answer(_ origin: FollowRequest.Origin, approve: Bool) async -> Bool {
        let index = requests.firstIndex { $0.origin == origin }
        let removed = index.map { requests[$0] }
        withAnimation(.snappy(duration: 0.2)) { requests.removeAll { $0.origin == origin } }
        do {
            if approve {
                try await FollowRequestsAPI.authorize(origin)
                approvedCount += 1
            } else {
                try await FollowRequestsAPI.reject(origin)
            }
            return true
        } catch let error as APIError where error.statusCode == 404 {
            return true
        } catch {
            if let index, let removed {
                withAnimation(.snappy(duration: 0.2)) {
                    requests.insert(removed, at: min(index, requests.count))
                }
            }
            ToastCenter.shared.show(String(localized: "요청에 답하지 못했어요"))
            return false
        }
    }
}

struct FollowRequestsView: View {
    @State private var store = FollowRequestStore.shared

    var body: some View {
        ReadingColumn(spacing: 0) {
            Color.clear.frame(height: 8)
            if !store.loaded {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if store.failed && store.requests.isEmpty {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await store.load() } })
                    .padding(.top, 60)
            } else if store.requests.isEmpty {
                ContentUnavailableView {
                    Text("기다리는 팔로우 요청이 없어요")
                } description: {
                    Text("팔로우를 직접 승인하면 새 팔로워가 여기서 기다려요. 프로필 편집에서 켤 수 있어요.")
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.requests) { request in
                        FollowRequestRow(request: request)
                        if request.id != store.requests.last?.id { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("팔로우 요청")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: store.approvedCount)
        .refreshable { await store.load() }
        .task { await store.load() }
    }
}

private struct FollowRequestRow: View {
    let request: FollowRequest
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let buttons = AnswerButtons(origin: request.origin, name: request.shownName)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    person
                    buttons
                }
            } else {
                HStack(spacing: 12) {
                    person
                    Spacer(minLength: 8)
                    buttons
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("followRequests.row.\(request.handle)")
    }

    private var person: some View {
        NavigationLink(value: request.route) {
            HStack(spacing: 12) {
                AvatarView(author: request.asAuthor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: request.shownName)
                        .typeScale(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(verbatim: "@\(request.handle)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let date = request.requestedAt {
                            Text(verbatim: "·")
                            Text(date.relativeShort)
                                .fixedSize()
                        }
                    }
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 승인·거절 한 쌍 — 요청 화면과 요청 알림이 같이 쓴다.
struct AnswerButtons: View {
    let origin: FollowRequest.Origin
    let name: String
    var onAnswered: (() -> Void)?
    @State private var busy = false

    var body: some View {
        HStack(spacing: 8) {
            Button("거절") { answer(approve: false) }
                .buttonStyle(.glass)
                .accessibilityIdentifier("followRequests.reject")
            Button("승인") { answer(approve: true) }
                .buttonStyle(.glassProminent)
                .tint(Palette.accentFill)
                .accessibilityIdentifier("followRequests.authorize")
        }
        .controlSize(.small)
        .font(.subheadline.weight(.semibold))
        .disabled(busy)
    }

    private func answer(approve: Bool) {
        busy = true
        Task {
            if await FollowRequestStore.shared.answer(origin, approve: approve) {
                onAnswered?()
                if approve {
                    ToastCenter.shared.show(String(localized: "\(name)님이 팔로워가 됐어요"))
                }
            }
            busy = false
        }
    }
}
