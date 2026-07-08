//
//  UnreadStore.swift
//  kurl
//

import Foundation
import Observation

/// 미읽음 알림 카운트의 단일 소유자 — 피드 탭·계정 탭의 벨이 각자 @State 로 같은
/// unread-count GET 을 치던 것(기동·포그라운드 복귀마다 2회)을 합친다.
/// 동시 refresh 는 한 비행으로 합쳐져 요청이 1건만 나간다.
@MainActor
@Observable
final class UnreadStore {
    static let shared = UnreadStore()

    private(set) var count: Int64 = 0
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    private init() {}

    func refresh() async {
        guard AuthStore.shared.isSignedIn else {
            count = 0
            return
        }
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task {
            // 실패하면 이전 값 유지 — 통신 오류로 점이 사라졌다 돌아오지 않게.
            count = (try? await NotificationsAPI.unreadCount()) ?? count
        }
        inFlight = task
        await task.value
        inFlight = nil
    }
}
