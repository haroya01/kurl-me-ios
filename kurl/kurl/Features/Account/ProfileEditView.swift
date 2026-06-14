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

            Section("소개") {
                TextField("자기소개를 적어보세요", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
                HStack {
                    Spacer()
                    Text("\(bio.count)/\(bioLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(bio.count > bioLimit ? .red : .secondary)
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
                        .disabled(!loaded || bio.count > bioLimit)
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

    private func load() async {
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
                if let img = newAvatar, let jpeg = img.jpegData(compressionQuality: 0.85) {
                    _ = try await ProfileAPI.uploadAvatar(jpegData: jpeg)
                }
                try await ProfileAPI.updateBio(bio.trimmingCharacters(in: .whitespacesAndNewlines))
                await AuthStore.shared.loadMe()
                onSaved()
                dismiss()
            } catch {
                self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }
}
