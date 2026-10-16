//
//  LockedPostGate.swift
//  kurl
//

import SwiftUI

struct LockedPostGate: View {
    let reason: PostLock.Reason
    let author: Author
    let model: PostDetailViewModel

    @State private var password = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch reason {
            case .followers:
                notice("팔로우하면 읽을 수 있어요")
                FollowButton(username: author.username) { following in
                    guard following else { return }
                    Task { await model.refreshLocked() }
                }
            case .password:
                notice("비밀번호가 걸린 글이에요")
                passwordForm
            case .region:
                notice("이 나라에서는 볼 수 없는 글이에요")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .accessibilityIdentifier("post.locked.\(reason.rawValue.lowercased())")
    }

    private func notice(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .typeScale(.lede)
            .foregroundStyle(Palette.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var opening: Bool { model.unlockState == .opening }

    private var errorMessage: String? {
        switch model.unlockState {
        case .wrongPassword: String(localized: "비밀번호가 맞지 않아요")
        case .tooManyAttempts: String(localized: "너무 많이 시도했어요. 잠시 뒤에 다시 해 주세요")
        case .failed(let message): message
        case .idle, .opening: nil
        }
    }

    private var passwordForm: some View {
        let row = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 10) {
            row {
                SecureField("비밀번호", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($fieldFocused)
                    .onSubmit(open)
                    .typeScale(.lede)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                    .accessibilityIdentifier("post.unlock.password")
                ToggleCapsuleButton(isOn: false, on: "열기", off: "열기", prominent: true, expandTap: 6, action: open)
                    .disabled(password.isEmpty || opening)
                    .opacity(password.isEmpty || opening ? 0.5 : 1)
                    .accessibilityIdentifier("post.unlock.open")
            }
            if let errorMessage {
                Text(errorMessage)
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("post.unlock.error")
            }
        }
        .onChange(of: password) { model.clearUnlockError() }
        .task {
            guard let preset = Config.consumeLaunchValue(after: "--unlock") else { return }
            password = preset
            open()
        }
    }

    private func open() {
        guard !password.isEmpty, !opening else { return }
        let typed = password
        Task { await model.unlock(password: typed) }
    }
}
