//
//  AuthStore.swift
//  kurl
//

import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import UIKit
import WidgetKit

enum AuthError: LocalizedError {
    /// 사용자가 브라우저 시트를 직접 닫음 — UI 는 조용히 무시한다.
    case cancelled
    case provider(String)
    case malformedCallback
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .provider: return String(localized: "로그인에 실패했습니다. 다시 시도해 주세요.")
        case .malformedCallback: return String(localized: "로그인 응답을 처리하지 못했습니다.")
        case .notSignedIn: return String(localized: "로그인이 필요합니다.")
        }
    }
}

enum SignInOutcome {
    case signedIn
    case twoFactorRequired
}

/// 로그인 상태의 단일 소유자. 흐름:
/// 1. `signIn()` — ASWebAuthenticationSession 으로 서버사이드 Google OAuth 를 그대로 타고,
///    `kurl://auth` 콜백의 일회용 코드를 토큰쌍으로 교환한다 (2FA 계정이면 challenge 보류).
/// 2. 토큰쌍은 Keychain 에만 저장. access 만료 시 APIClient 가 `refreshTokens()` 를 불러
///    rotation(+grace) 으로 새 쌍을 받는다 — 동시 401 은 단일 비행으로 합쳐진다.
@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var isSignedIn = false
    private(set) var me: Me?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var refreshToken: String?
    @ObservationIgnored private var pendingChallenge: String?
    @ObservationIgnored private var refreshTask: Task<Void, Error>?
    /// 세션 세대 — forgetSession 마다 증가. 비행 중이던 refresh 가 로그아웃 뒤에 토큰을
    /// 되살리지 못하게(adopt 직전 epoch 일치 확인) 막는 단조 가드.
    @ObservationIgnored private var sessionEpoch = 0
    @ObservationIgnored private var activeSession: ASWebAuthenticationSession?
    @ObservationIgnored private var appleDelegate: AppleAuthDelegate?
    @ObservationIgnored private let presenter = WebAuthPresenter()

    private static let accessAccount = "access-token"
    private static let refreshAccount = "refresh-token"

    private init() {
        if Config.useMocks {
            // 목 모드 = 항상 로그인된 상태. Keychain·네트워크를 건드리지 않는다.
            // `--logged-out` = 로그아웃 게이트(추천·구독함) 스크린샷 검증용 진입로.
            if ProcessInfo.processInfo.arguments.contains("--logged-out") { return }
            isSignedIn = true
            me = Me(id: 1, email: "mock@kurl.me", username: "honggildong", avatarUrl: nil, role: "ADMIN")
            return
        }
        accessToken = Keychain.load(account: Self.accessAccount)
        refreshToken = Keychain.load(account: Self.refreshAccount)
        isSignedIn = refreshToken != nil
        if isSignedIn {
            Task { await loadMe() }
        }
    }

    var bearerToken: String? { accessToken }

    // MARK: 로그인

    func signIn() async throws -> SignInOutcome {
        let callbackURL = try await startBrowserDance()
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let reason = value("error") {
            throw AuthError.provider(reason)
        }
        if let challenge = value("challenge") {
            pendingChallenge = challenge
            return .twoFactorRequired
        }
        guard let code = value("code") else {
            throw AuthError.malformedCallback
        }
        adopt(try await AuthAPI.exchange(code: code))
        return .signedIn
    }

    func completeTwoFactor(code: String, recovery: Bool) async throws {
        guard let challenge = pendingChallenge else { throw AuthError.notSignedIn }
        adopt(try await AuthAPI.verifyTwoFactor(challenge: challenge, code: code, recovery: recovery))
        pendingChallenge = nil
    }

    // MARK: Apple 로그인 (네이티브 — 브라우저 왕복 없음)

    /// 공식 SignInWithAppleButton 의 onRequest 에서 호출 — 스코프와 nonce 해시를 싣고
    /// 원문 nonce 를 돌려준다. 완료 시 `completeApple(_:rawNonce:)` 에 그대로 전달할 것.
    static func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) -> String {
        let raw = randomNonce()
        request.requestedScopes = [.email]
        request.nonce = sha256Hex(raw)
        return raw
    }

    /// 버튼/프로그램 경로 공용 본선 — identityToken 을 서버로 보내 토큰쌍으로 바꾼다.
    /// 서버는 nonce 해시 일치까지 검증하므로 다른 세션의 토큰은 여기서 죽는다.
    func completeApple(
        _ result: Result<ASAuthorization, Error>, rawNonce: String
    ) async throws -> SignInOutcome {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                throw AuthError.cancelled
            }
            throw AuthError.provider(error.localizedDescription)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else { throw AuthError.malformedCallback }
            let outcome = try await AuthAPI.appleLogin(identityToken: identityToken, nonce: rawNonce)
            if let challenge = outcome.challenge {
                pendingChallenge = challenge
                return .twoFactorRequired
            }
            guard let access = outcome.accessToken, let refresh = outcome.refreshToken else {
                throw AuthError.malformedCallback
            }
            adopt(TokenPair(accessToken: access, refreshToken: refresh))
            return .signedIn
        }
    }

    /// 버튼이 없는 자리(좋아요·팔로우 알럿 등)의 Apple 로그인 — 시스템 시트를 직접 띄운다.
    func signInWithApple() async throws -> SignInOutcome {
        let raw = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = Self.sha256Hex(raw)
        let result: Result<ASAuthorization, Error> = await withCheckedContinuation { continuation in
            let delegate = AppleAuthDelegate { [weak self] result in
                Task { @MainActor in self?.appleDelegate = nil }
                continuation.resume(returning: result)
            }
            // 시트가 떠 있는 동안 delegate 를 강하게 쥔다 — activeSession 과 같은 이유.
            appleDelegate = delegate
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
        }
        return try await completeApple(result, rawNonce: raw)
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func startBrowserDance() async throws -> URL {
        let url = Config.apiBase.appendingPathComponent(Config.apiPrefix + "/auth/mobile/start")
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme("kurl")
            ) { [weak self] callbackURL, error in
                Task { @MainActor in self?.activeSession = nil }
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let authError = error as? ASWebAuthenticationSessionError,
                          authError.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.malformedCallback)
                }
            }
            session.presentationContextProvider = presenter
            // start() 이후에도 세션을 강하게 쥐고 있어야 시트가 유지된다.
            activeSession = session
            session.start()
        }
    }

    // MARK: 토큰 수명

    /// 단일 비행 리프레시 — 동시 401 들이 각자 rotation 을 돌려 grace 를 소모하지 않게 한다.
    func refreshTokens() async throws {
        if Config.useMocks { return }
        if let running = refreshTask {
            return try await running.value
        }
        guard let current = refreshToken else { throw AuthError.notSignedIn }
        let epoch = sessionEpoch
        let task = Task<Void, Error> {
            do {
                let pair = try await AuthAPI.refresh(refreshToken: current)
                // 리프레시 도중 로그아웃(forgetSession)이 끼었으면 토큰을 되살리지 않는다.
                guard epoch == sessionEpoch else { throw AuthError.notSignedIn }
                adopt(pair)
            } catch APIError.http(let status) where status == 401 {
                // 리프레시 토큰 자체가 죽음 — 로컬 세션 폐기 (다른 기기 세션은 서버가 유지)
                forgetSession()
                throw AuthError.notSignedIn
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    func signOut() {
        // 뒷정리에 쓸 토큰을 스냅샷 — forgetSession 이후엔 저장소가 비어 있다.
        let access = accessToken
        let refresh = refreshToken
        let device = Config.useMocks ? nil : PushRegistrar.storedToken
        forgetSession()
        Task {
            if let device, let access {
                // 디바이스 등록 해제 — 로그아웃한 계정의 푸시가 이 기기로 오지 않게.
                try? await AuthAPI.unregisterDevice(token: device, bearer: access)
            }
            if let refresh {
                try? await AuthAPI.logout(refreshToken: refresh)
            }
        }
    }

    func loadMe() async {
        guard isSignedIn else { return }
        me = try? await AuthAPI.me()
    }

    private func adopt(_ pair: TokenPair) {
        accessToken = pair.accessToken
        refreshToken = pair.refreshToken
        Keychain.save(pair.accessToken, account: Self.accessAccount)
        Keychain.save(pair.refreshToken, account: Self.refreshAccount)
        if !isSignedIn {
            isSignedIn = true
            Task { await loadMe() }
            PushRegistrar.syncAfterSignIn()
        }
    }

    private func forgetSession() {
        // 세대를 올려 비행 중 refresh 의 adopt 를 무효화(토큰 부활 레이스 차단).
        sessionEpoch &+= 1
        accessToken = nil
        refreshToken = nil
        pendingChallenge = nil
        me = nil
        isSignedIn = false
        Keychain.delete(account: Self.accessAccount)
        Keychain.delete(account: Self.refreshAccount)
        tearDownSessionState()
    }

    /// 로그아웃 시 기기 로컬에 남은 *이전 계정* 자취를 전부 폐기한다 — 같은 기기에서 다른
    /// 계정으로 로그인했을 때 A 의 오프라인 사본·읽음 기록·북마크·분석 위젯이 B 에게 보이지
    /// 않게(프라이버시). refresh 토큰이 죽어 세션이 끊긴 경로(refreshTokens 401)도 여기를 탄다.
    private func tearDownSessionState() {
        BookmarkStore.shared.reset()
        PostReadStore.shared.reset()
        OfflineStore.shared.removeAll()
        AnalyticsSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

/// 프로그램 경로 Apple 로그인의 delegate + 프레젠테이션 앵커.
private final class AppleAuthDelegate: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        completion(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: any Error
    ) {
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
