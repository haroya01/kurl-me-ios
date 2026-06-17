//
//  ChooseUsernameView.swift
//  kurl
//

import SwiftUI

/// 가입 직후 핸들 정하기 — username 이 비어 있으면(특히 애플 신규 유저) RootView 가 풀스크린으로
/// 띄운다. 핸들 없이는 u/·p/ 주소가 안 서므로 닫을 수 없다. 정하면 me 가 갱신되며 자동으로 사라진다.
/// 형식·중복 검증은 서버 몫(프로필 편집과 같은 규칙) — 여기선 형식만 미리 막아 왕복을 줄인다.
struct ChooseUsernameView: View {
    var onDone: () -> Void = {}

    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var username = ""
    @State private var saving = false
    @State private var serverError: String?

    private var trimmed: String { username.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool {
        trimmed.range(of: "^[a-z0-9][a-z0-9_]{2,15}$", options: .regularExpression) != nil
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            BrandMist()
                .frame(height: 360)
                .frame(maxHeight: .infinity, alignment: .top)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                KurlMark(drawn: [true, true, true])
                    .frame(width: 64, height: 39)
                Text("사용자 이름을 정해 주세요")
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 16)
                Text("kurl.me/u/ 주소에 쓰여요. 나중에 바꿀 수 있어요.")
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)

                HStack(spacing: 1) {
                    Text("kurl.me/u/").foregroundStyle(Palette.secondary)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: username) { _, value in
                            let cleaned = value.lowercased()
                                .filter { $0.isNumber || ("a"..."z").contains($0) || $0 == "_" }
                            username = String(cleaned.prefix(16))
                            serverError = nil
                        }
                }
                .font(.system(size: 16))
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 24)

                Group {
                    if let serverError {
                        Text(serverError).foregroundStyle(Palette.danger)
                    } else if !trimmed.isEmpty && !valid {
                        Text("영문 소문자·숫자·_ 3~16자, 첫 글자는 영문이나 숫자")
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .font(.caption)
                .padding(.top, 8)

                Spacer()

                Button {
                    submit()
                } label: {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(.white) }
                        Text("시작하기").font(.system(size: 16 * unit, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        valid ? GlassTokens.prominentTint : Color.secondary.opacity(0.4),
                        in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!valid || saving)
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter + 4)
            .padding(.top, 60)
            .padding(.bottom, 28)
        }
        .interactiveDismissDisabled(true)
    }

    private func submit() {
        guard valid, !saving else { return }
        saving = true
        serverError = nil
        Task {
            defer { saving = false }
            do {
                try await ProfileAPI.update(username: trimmed)
                await AuthStore.shared.loadMe()
                onDone()
            } catch {
                switch error {
                case APIError.http(let status):
                    serverError = status == 409
                        ? String(localized: "이미 사용 중인 이름이에요.")
                        : String(localized: "사용할 수 없는 이름이에요.")
                case APIError.transport:
                    // 통신 실패는 입력 잘못이 아니므로 다시 시도를 분명히 — 버튼이 곧 재시도다.
                    serverError = String(localized: "네트워크에 연결할 수 없어요. 다시 시도해 주세요.")
                default:
                    serverError = (error as? APIError)?.localizedDescription
                        ?? error.localizedDescription
                }
            }
        }
    }
}
