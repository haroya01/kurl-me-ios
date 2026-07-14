//
//  ProfileEditView.swift
//  kurl
//

import ImageIO
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
    @State private var bioLoaded = false
    @State private var hideFollowerCount = false
    @State private var initialHideFollowerCount = false
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
                                .typeScale(.meta)
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
                    Text(verbatim: "blog.kurl.me/@")
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
                .typeScale(.body)
                if let usernameError {
                    Text(usernameError).font(.caption).foregroundStyle(Palette.danger)
                } else if usernameChanged {
                    Text("이전 이름은 30일간 예약돼 기존 링크가 바로 깨지지 않아요.")
                        .font(.caption).foregroundStyle(Palette.secondary)
                } else {
                    // 바꾸기 전에도 제약을 미리 알린다 — 첫 편집 때 "왜 안 바뀌지"를 없앤다(§10 조용한 각주).
                    Text("이름을 바꾸면 30일 동안 다시 바꿀 수 없어요.")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
            }

            Section("소개") {
                TextField("자기소개를 적어보세요", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
                if loaded && !bioLoaded {
                    HStack(spacing: 6) {
                        Text("기존 소개글을 불러오지 못했어요.")
                            .font(.caption)
                            .foregroundStyle(Palette.secondary)
                        Button("다시 불러오기") { Task { await loadBio() } }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.link)
                    }
                }
                HStack {
                    Spacer()
                    Text(String(localized: "\(bio.count) / \(bioLimit)자"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(bio.count > bioLimit ? Palette.danger : Palette.secondary)
                }
            }

            Section {
                Toggle(isOn: $hideFollowerCount) {
                    Text("팔로워 수 숨기기")
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.accent)
                // 현재값을 못 받았으면 잠근다 — 잘못된 기준으로 서버 값을 덮어쓰지 않도록.
                .disabled(!bioLoaded)
            } footer: {
                Text("켜면 내 프로필과 목록에서 팔로워·팔로잉 수가 보이지 않아요. 팔로우는 그대로 돼요.")
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
                RemoteImage(url: u) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(Palette.hairline)
                    }
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
        await loadBio()
        loaded = true
    }

    /// 실패와 "원래 빈 소개"를 구분한다 — 실패를 "" 로 뭉개면 저장 때 서버 소개글이 지워진다.
    /// 같은 GET 이 팔로워 숨김 여부도 내려주므로 토글 프리필도 여기서 함께 시드한다.
    private func loadBio() async {
        do {
            let profile = try await ProfileAPI.myProfile()
            bio = profile.bio ?? ""
            bioLoaded = true
            hideFollowerCount = profile.hideFollowerCount
            initialHideFollowerCount = profile.hideFollowerCount
        } catch {
            bioLoaded = false
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let img = await Self.downsample(data, maxSide: 512) else { return }
        newAvatar = img
    }

    /// 아바타는 작게 — 512px 한 변으로 줄여 업로드(불필요한 대용량 차단). 고해상도 원본이
    /// 메인 스레드를 막지 않게 nonisolated + ImageIO 썸네일(전체 디코드 없음)로 처리한다.
    private nonisolated static func downsample(_ data: Data, maxSide: CGFloat) async -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // EXIF 회전 반영
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                // 프로필 PUT 을 먼저 — 거절(중복·형식)나면 아바타는 손대지 않는다.
                // 소개글 로드에 실패했고 직접 쓴 것도 없으면 bio 는 보내지 않는다(서버 값 보존).
                let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
                try await ProfileAPI.update(
                    username: usernameChanged ? trimmedUsername : nil,
                    bio: bioLoaded || !trimmedBio.isEmpty ? trimmedBio : nil,
                    // 바뀐 값일 때만 — 프리필을 못 받았으면(false 기본) 켠 경우에만 보내 오설정 방지.
                    hideFollowerCount: hideFollowerCount != initialHideFollowerCount ? hideFollowerCount : nil)
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
        if let status = (error as? APIError)?.statusCode {
            switch status {
            case 409: return String(localized: "이미 사용 중인 이름이에요.")
            case 400: return String(localized: "사용할 수 없는 이름이에요.")
            default: break
            }
        }
        return (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}
