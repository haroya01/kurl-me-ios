import SwiftUI
import UIKit

// MARK: 흔들기 감지

extension Notification.Name {
    static let deviceDidShake = Notification.Name("kurl.deviceDidShake")
}

/// 흔들기는 first responder 에서 시작해 창까지 올라온다. 받으려고 빈 뷰 컨트롤러를 first responder 로 심어 두면
/// iOS 26.5 에서 메뉴가 열릴 때마다 키보드가 함께 올라온다 — 아무것도 first responder 로 두지 않고 창에서 받는다.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension View {
    /// 기기를 흔들면 action — 관리자 진단 진입에 쓴다(게이트는 호출측).
    func onShake(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in action() }
    }
}

// MARK: 관리자 진단 화면

/// 흔들면 뜨는 **관리자 전용** 진단 — 현재 API·앱·유저·기기 정보를 한 화면에. 일반 유저는
/// 게이트(role==ADMIN)에서 막힌다. 민감한 토큰 값은 안 보이고 존재 여부만 노출한다.
struct AdminDebugView: View {
    @Environment(\.dismiss) private var dismiss
    private var me: Me? { AuthStore.shared.me }
    /// 디버그 값 행(mono) — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var rowSize: CGFloat = 13

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
                // MetricKit 진단(크래시·행) — 최근 페이로드가 기기에 남는다(CrashObservatory).
                // 목록이 비어 있는 것이 곧 "관측되는 무사고"다.
                Section("크래시 진단") {
                    let reports = CrashObservatory.recentReports()
                    if reports.isEmpty {
                        row("수집된 진단", "없음 (무사고)")
                    } else {
                        ForEach(reports.prefix(10), id: \.self) { url in
                            ShareLink(item: url) {
                                HStack {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: rowSize, design: .monospaced))
                                        .foregroundStyle(Palette.danger)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: rowSize))
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                        }
                    }
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
        .font(.system(size: rowSize).monospaced())
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
