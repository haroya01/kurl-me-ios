//
//  SettingsView.swift
//  kurl
//

import SwiftUI
import UIKit
import UserNotifications

/// 설정 — 법적 문서·버전·회원 탈퇴. 기능 나열식 화면을 피해온 앱이지만
/// 이 셋은 없으면 안 되는 최소 집합이다(App Store 5.1.1(v): 앱 내 계정 삭제 필수).
struct SettingsView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false
    /// 버전 문자열(mono) — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var versionSize: CGFloat = 14
    @State private var pushStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        ReadingColumn(spacing: 0) {
            if auth.isSignedIn {
                // 계정 관리 — 내 계정 화면이 블로그가 되면서 프로필 편집·로그아웃이 이리로 모인다.
                RailHeading("계정")
                    .padding(.top, 24)
                    .padding(.bottom, 4)
                NavigationLink {
                    ProfileEditView(currentAvatarUrl: auth.me?.avatarUrl)
                } label: {
                    HStack(spacing: 10) {
                        settingIcon("person.crop.circle")
                        Text("프로필 편집")
                            .typeScale(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline()
                Button {
                    auth.signOut()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14))
                            .frame(width: 22)
                        Text("로그아웃")
                            .typeScale(.body)
                        Spacer()
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
            }

            RailHeading("알림")
                .padding(.top, auth.isSignedIn ? 28 : 24)
                .padding(.bottom, 4)
            // 미결정이면 여기서 권한 시트까지. 한 번 결정된 뒤의 변경은 시스템 설정 영역이다 —
            // 시트를 다시 띄울 수 없으므로 가짜 토글 대신 딥링크로 보낸다.
            Button(action: handlePushRow) {
                HStack(spacing: 10) {
                    settingIcon("bell.badge")
                    Text("푸시 알림")
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if let label = pushStatusLabel {
                        Text(label)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    Image(systemName: pushStatus == .notDetermined ? "chevron.right" : "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .task { await reloadPushStatus() }
            if pushStatus == .denied {
                // 끈 뒤엔 시트가 안 뜨고 화살표가 시스템 설정으로 점프한다 — 그 점프를 미리 알린다.
                Text("시스템 설정에서 켤 수 있어요")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding(.leading, 32)
                    .padding(.bottom, 4)
            }
            if auth.isSignedIn {
                // 종류별 뮤트는 인증 설정(내 계정에 저장) — 위 푸시 권한(시스템)과 층이 다르다.
                Hairline()
                NavigationLink {
                    NotificationPreferencesView()
                } label: {
                    HStack(spacing: 10) {
                        settingIcon("slider.horizontal.3")
                        Text("알림 종류")
                            .typeScale(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            RailHeading("정책")
                .padding(.top, 28)
                .padding(.bottom, 4)
            linkRow("이용약관", icon: "doc.text") { open(path: "terms") }
            Hairline()
            linkRow("개인정보처리방침", icon: "hand.raised") { open(path: "privacy") }

            RailHeading("앱")
                .padding(.top, 28)
                .padding(.bottom, 4)
            HStack(spacing: 10) {
                settingIcon("info.circle")
                Text("버전")
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(Self.version)
                    .font(.system(size: versionSize).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 13)

            if auth.isSignedIn {
                RailHeading("안전")
                    .padding(.top, 28)
                    .padding(.bottom, 4)
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    HStack(spacing: 10) {
                        settingIcon("hand.raised")
                        Text("차단한 사용자")
                            .typeScale(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Hairline()
                    .padding(.top, 16)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    HStack(spacing: 10) {
                        if deleting {
                            ProgressView()
                                .frame(width: 22)
                        } else {
                            Image(systemName: "person.crop.circle.badge.minus")
                                .font(.system(size: 14))
                                .frame(width: 22)
                        }
                        Text("회원 탈퇴")
                            .typeScale(.body)
                    }
                    .foregroundStyle(Palette.danger)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
                .padding(.top, 18)
                .disabled(deleting)
            }
        }
        .navigationTitle("설정")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            // 시스템 설정에 다녀온 뒤 상태 라벨을 따라잡는다.
            if phase == .active {
                Task { await reloadPushStatus() }
            }
        }
        // 회원 탈퇴 확인 — 두 단계 확인을 한 알럿으로 합쳤다. confirmationDialog 은 세로·가로·iPad
        // 어디서나 부리 팝오버로 바뀌어 트리거와 무관한 화면 중앙에 붕 떴다. 알럿은 항상 중앙 모달이라
        // 새지 않는다. 파괴적 동작이라 결과·불가역을 한 번에 알리고 되묻는다(탈퇴 = destructive).
        .alert("정말 탈퇴할까요?", isPresented: $confirmDelete) {
            Button("탈퇴", role: .destructive) { deleteAccount() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("글·시리즈·댓글이 모두 삭제 대상이 됩니다.")
                + Text(verbatim: "\n")
                + Text("이 동작은 되돌릴 수 없습니다.")
        }
        .alert("탈퇴하지 못했습니다", isPresented: $deleteFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("잠시 후 다시 시도해 주세요.")
        }
    }

    private var pushStatusLabel: LocalizedStringKey? {
        switch pushStatus {
        case .authorized, .provisional, .ephemeral: return "켜짐"
        case .denied: return "꺼짐"
        default: return nil
        }
    }

    private func reloadPushStatus() async {
        pushStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func handlePushRow() {
        if pushStatus == .notDetermined {
            Task {
                _ = await PushRegistrar.requestAndRegister()
                await reloadPushStatus()
            }
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }

    private func settingIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(Palette.accentMarker)
            .frame(width: 22)
    }

    private func linkRow(
        _ title: LocalizedStringKey, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                settingIcon(icon)
                Text(title)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    /// 약관·방침은 웹과 단일 원문 — 로케일 경로로 연다.
    private func open(path: String) {
        if let url = URL(string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/\(path)") {
            openURL(url)
        }
    }

    private func deleteAccount() {
        guard !deleting else { return }
        deleting = true
        Task {
            defer { deleting = false }
            do {
                try await AuthAPI.deleteAccount()
                auth.signOut()
                // 토스트는 루트(ToastHost)에 떠 dismiss 뒤에도 살아남는다 — 화면이 사라져 무피드백이던 자리.
                ToastCenter.shared.show(String(localized: "계정을 삭제했습니다"))
                dismiss()
            } catch {
                deleteFailed = true
            }
        }
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
