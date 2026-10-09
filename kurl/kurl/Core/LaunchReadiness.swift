//
//  LaunchReadiness.swift
//  kurl
//

import Observation

/// 첫 화면이 그릴 거리를 받았는가 — 스플래시가 고정 시간 대신 이 신호(또는 짧은 상한)에 걷힌다.
@MainActor
@Observable
final class LaunchReadiness {
    static let shared = LaunchReadiness()

    private(set) var firstFeedSettled = false

    private init() {}

    func markFirstFeedSettled() {
        guard !firstFeedSettled else { return }
        firstFeedSettled = true
    }
}
