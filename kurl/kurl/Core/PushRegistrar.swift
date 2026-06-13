//
//  PushRegistrar.swift
//  kurl
//

import SwiftUI
import UserNotifications

/// APNs 등록의 단일 소유자. 토큰 수명과 계정 수명이 어긋나는 두 지점을 잇는다:
/// - 토큰은 기기 것 — 권한 허용 후 시스템이 주고, OS 가 임의로 갈아끼울 수 있다(콜백마다 서버 upsert).
/// - 등록은 계정 것 — 로그인하면 보관된 토큰을 새 계정으로 옮기고(서버가 소유자 reassign),
///   로그아웃 직전에 bearer 가 살아 있을 때 서버에서 지운다. 토큰 자체는 다음 로그인을 위해 남긴다.
enum PushRegistrar {
    private static let tokenKey = "apnsToken"

    static var storedToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    /// 앱 시작 시 — 이미 허용된 기기라면 조용히 재등록해 토큰 갱신 콜백을 계속 받는다.
    static func bootstrap() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// 설정의 알림 행 — 권한 시트를 띄우고 허용되면 원격 등록까지. 이미 거부된 기기면
    /// 시트가 다시 뜨지 않으므로 false 를 돌려 호출측이 시스템 설정으로 안내한다.
    static func requestAndRegister() async -> Bool {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .denied { return false }
        let granted =
            (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    /// 시스템 토큰 콜백 — 보관 후, 로그인 상태면 즉시 서버 upsert.
    static func tokenReceived(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        guard AuthStore.shared.isSignedIn, !Config.useMocks else { return }
        Task { try? await AuthAPI.registerDevice(token: token) }
    }

    /// 로그인 직후 — 기기에 남은 토큰을 이 계정으로 등록(다른 계정 것이었어도 서버가 갈아끼움).
    /// 로그아웃 쪽 짝은 AuthStore.signOut 이 토큰 스냅샷과 함께 직접 처리한다.
    static func syncAfterSignIn() {
        guard let token = storedToken, !Config.useMocks else { return }
        Task { try? await AuthAPI.registerDevice(token: token) }
    }
}

/// UIKit 콜백 수신 전용 — 토큰 전달과 포그라운드 표시 정책만 담당하는 얇은 어댑터.
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PushRegistrar.bootstrap()
        // AsyncImage 가 shared 세션을 탄다 — 디스크 캐시를 넉넉히 잡아 오프라인 사본의
        // 커버·본문 이미지가 기본 10MB 에서 밀려나지 않게 한다(본문 텍스트는 OfflineStore 확정).
        URLCache.shared = URLCache(
            memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
        #if DEBUG
        // 뷰가 생기기 전에 — `--post` 진입로의 상세 로드와 시드가 경합하지 않게 여기서.
        OfflineSeed.runIfRequested()
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrar.tokenReceived(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // 시뮬레이터·프로비저닝 부재 — 푸시 없이도 앱은 그대로 동작해야 한다.
    }

    /// 앱이 떠 있는 동안 도착한 푸시도 배너로 — 알림 센터에 묻히지 않게.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
