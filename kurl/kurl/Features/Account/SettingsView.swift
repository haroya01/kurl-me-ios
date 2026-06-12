//
//  SettingsView.swift
//  kurl
//

import SwiftUI

/// 설정 — 법적 문서·버전·회원 탈퇴. 기능 나열식 화면을 피해온 앱이지만
/// 이 셋은 없으면 안 되는 최소 집합이다(App Store 5.1.1(v): 앱 내 계정 삭제 필수).
struct SettingsView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var finalConfirmDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            RailHeading("정책")
                .padding(.top, 24)
                .padding(.bottom, 4)
            linkRow("이용약관") { open(path: "terms") }
            Hairline()
            linkRow("개인정보처리방침") { open(path: "privacy") }

            RailHeading("앱")
                .padding(.top, 28)
                .padding(.bottom, 4)
            HStack {
                Text("버전")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(Self.version)
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 13)

            if auth.isSignedIn {
                Hairline()
                    .padding(.top, 16)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    if deleting {
                        ProgressView()
                    } else {
                        Text("회원 탈퇴")
                            .font(.system(size: 15))
                    }
                }
                .padding(.top, 18)
                .disabled(deleting)
            }
        }
        .navigationTitle("설정")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "계정을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("계속", role: .destructive) { finalConfirmDelete = true }
        } message: {
            Text("글·시리즈·댓글이 모두 삭제 대상이 됩니다.")
        }
        .alert("정말 탈퇴할까요?", isPresented: $finalConfirmDelete) {
            Button("탈퇴", role: .destructive) { deleteAccount() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 동작은 되돌릴 수 없습니다.")
        }
        .alert("탈퇴하지 못했습니다", isPresented: $deleteFailed) {
            Button("확인", role: .cancel) {}
        }
    }

    private func linkRow(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
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
