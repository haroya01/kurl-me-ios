//
//  ProfileEditView.swift
//  kurl
//

import PhotosUI
import SwiftUI

/// 프로필 편집 — 아바타·소개글. 내 계정에서 푸시로 들어온다(저장=내비바 우측).
/// 아바타는 presign→S3→commit, 소개글은 부분 PUT(테마·소셜 보존). 저장 후 me 를 새로고침한다.
struct ProfileEditView: View {
    let currentAvatarUrl: String?
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var initialUsername = ""
    @State private var bio = ""
    @State private var loaded = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var newAvatar: UIImage?
    @State private var saving = false
    @State private var error: String?

    private let bioLimit = 280

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        VStack(spacing: 8) {
                            avatarPreview
                            Text("사진 변경")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.link)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("사용자 이름") {
                HStack(spacing: 1) {
                    Text("kurl.me/u/")
                        .foregroundStyle(Palette.secondary)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: username) { _, value in
                            // 서버 규칙(소문자·숫자·_, 16자)에 맞춰 입력 단계에서 정리.
                            let cleaned = value.lowercased()
                                .filter { $0.isNumber || ("a"..."z").contains($0) || $0 == "_" }
                            let capped = String(cleaned.prefix(16))
                            if capped != value { username = capped }
                        }
                }
                .font(.system(size: 15))
                if let usernameError {
                    Text(usernameError).font(.caption).foregroundStyle(Palette.danger)
                } else if usernameChanged {
                    Text("이전 이름은 30일간 예약돼 기존 링크가 바로 깨지지 않아요.")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
            }

            Section("소개") {
                TextField("자기소개를 적어보세요", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
                HStack {
                    Spacer()
                    Text("\(bio.count)/\(bioLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(bio.count > bioLimit ? Palette.danger : Palette.secondary)
                }
            }
        }
        .navigationTitle("프로필 편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("저장") { save() }
                        .disabled(!loaded || bio.count > bioLimit || usernameError != nil)
                }
            }
        }
        .task { await load() }
        .onChange(of: pickerItem) { _, item in
            Task { await loadPicked(item) }
        }
        .alert(
            "저장하지 못했습니다",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    @ViewBuilder private var avatarPreview: some View {
        Group {
            if let newAvatar {
                Image(uiImage: newAvatar).resizable().scaledToFill()
            } else if let url = currentAvatarUrl, let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: {
                    Circle().fill(Palette.hairline)
                }
            } else {
                Circle().fill(Palette.chipBg)
                    .overlay { Image(systemName: "camera").foregroundStyle(Palette.secondary) }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 1) }
    }

    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }
    private var usernameChanged: Bool { !trimmedUsername.isEmpty && trimmedUsername != initialUsername }
    /// 서버와 같은 규칙: 소문자·숫자·_, 3~16자, 첫 글자는 영문/숫자. 바뀐 값일 때만 검사.
    private var usernameError: String? {
        guard usernameChanged else { return nil }
        let ok = trimmedUsername.range(
            of: "^[a-z0-9][a-z0-9_]{2,15}$", options: .regularExpression) != nil
        return ok ? nil : String(localized: "영문 소문자·숫자·_ 3~16자, 첫 글자는 영문이나 숫자")
    }

    private func load() async {
        await AuthStore.shared.loadMe()
        let current = AuthStore.shared.me?.username ?? ""
        username = current
        initialUsername = current
        bio = (try? await ProfileAPI.myBio()) ?? ""
        loaded = true
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        newAvatar = downsample(img, maxSide: 512)
    }

    /// 아바타는 작게 — 512px 한 변으로 줄여 업로드(불필요한 대용량 차단).
    private func downsample(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                // 프로필 PUT 을 먼저 — 거절(중복·형식)나면 아바타는 손대지 않는다.
                try await ProfileAPI.update(
                    username: usernameChanged ? trimmedUsername : nil,
                    bio: bio.trimmingCharacters(in: .whitespacesAndNewlines))
                if let img = newAvatar, let jpeg = img.jpegData(compressionQuality: 0.85) {
                    _ = try await ProfileAPI.uploadAvatar(jpegData: jpeg)
                    newAvatar = nil  // 성공 — 재시도해도 다시 안 올린다.
                }
                await AuthStore.shared.loadMe()
                onSaved()
                dismiss()
            } catch {
                self.error = usernameSaveError(error)
            }
        }
    }

    /// 서버 거절을 사람 말로 — 409=중복, 400=형식. 그 외는 일반 메시지.
    private func usernameSaveError(_ error: Error) -> String {
        if case APIError.http(let status) = error {
            switch status {
            case 409: return String(localized: "이미 사용 중인 이름이에요.")
            case 400: return String(localized: "사용할 수 없는 이름이에요.")
            default: break
            }
        }
        return (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}
