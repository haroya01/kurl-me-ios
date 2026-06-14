//
//  AdminDebug.swift
//  kurl
//

import SwiftUI
import UIKit

// MARK: 흔들기 감지

extension Notification.Name {
    static let deviceDidShake = Notification.Name("kurl.deviceDidShake")
}

/// 흔들기(좌우 모션)를 잡는 0픽셀 감지기 — 모션 이벤트는 first responder→responder 체인으로
/// 올라오므로, 화면 어딘가에 first responder 가 될 빈 VC 하나만 심어 두면 잡힌다.
private struct ShakeDetector: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeViewController { ShakeViewController() }
    func updateUIViewController(_ vc: ShakeViewController, context: Context) {}
}

private final class ShakeViewController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension View {
    /// 기기를 흔들면 action — 관리자 진단 진입에 쓴다(게이트는 호출측).
    func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeDetector().frame(width: 0, height: 0).accessibilityHidden(true))
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in action() }
    }
}

// MARK: 관리자 진단 화면

/// 흔들면 뜨는 **관리자 전용** 진단 — 현재 API·앱·유저·기기 정보를 한 화면에. 일반 유저는
/// 게이트(role==ADMIN)에서 막힌다. 민감한 토큰 값은 안 보이고 존재 여부만 노출한다.
struct AdminDebugView: View {
    @Environment(\.dismiss) private var dismiss
    private var me: Me? { AuthStore.shared.me }

    var body: some View {
        NavigationStack {
            List {
                Section("앱") {
                    row("버전", "\(appVersion) (\(appBuild))")
                    row("번들 ID", Bundle.main.bundleIdentifier ?? "—")
                    row("환경", environmentLabel)
                }
                Section("API / 설정") {
                    row("API base", Config.apiBase.absoluteString)
                    row("API prefix", Config.apiPrefix)
                    row("목 모드", Config.useMocks ? "ON" : "OFF")
                    row("오프라인 시뮬", Config.simulateOffline ? "ON" : "OFF")
                    row("로케일", Config.preferredLanguageTag)
                }
                Section("계정") {
                    row("로그인", AuthStore.shared.isSignedIn ? "예" : "아니오")
                    row("id", me?.id.map(String.init) ?? "—")
                    row("username", me?.username ?? "—")
                    row("email", me?.email ?? "—")
                    row("role", me?.role ?? "—")
                    row("푸시 토큰", PushRegistrar.storedToken != nil ? "등록됨" : "없음")
                }
                Section("기기") {
                    row("모델", UIDevice.current.model)
                    row("OS", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                }
            }
            .navigationTitle("관리자 진단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.system(size: 13).monospaced())
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var environmentLabel: String {
        #if DEBUG
        return "DEBUG"
        #else
        return "RELEASE"
        #endif
    }
}
