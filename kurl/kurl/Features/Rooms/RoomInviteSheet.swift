//
//  RoomInviteSheet.swift
//  kurl
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct RoomInviteSheet: View {
    let roomId: Int64
    let roomName: String

    @State private var invite: RoomInvite?
    @State private var failed: String?
    @State private var limit = 0
    @State private var expiry = 0
    @State private var approval = false
    @State private var making = false
    @Environment(\.dismiss) private var dismiss

    private static let limits = [0, 5, 10, 20, 50]
    private static let expiries: [(days: Int, label: LocalizedStringKey)] = [(0, "안 함"), (1, "1일"), (7, "7일")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let invite, let url = invite.shareURL {
                        VStack(spacing: 14) {
                            QRCodeImage(text: url.absoluteString)
                                .frame(width: 180, height: 180)
                                .accessibilityLabel(Text("초대 QR 코드"))
                            Text(url.absoluteString)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                            ShareLink(item: url, subject: Text(roomName)) {
                                Label("초대 링크 보내기", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(GlassTokens.prominentTint)
                            .accessibilityIdentifier("roomInvite.share")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else if let failed {
                        Text(failed).foregroundStyle(.red)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } footer: {
                    if let invite {
                        Text("코드 \(invite.code) · \(usage(invite))")
                    }
                }
                Section {
                    DisclosureGroup("고급") {
                        Picker("사용 횟수", selection: $limit) {
                            ForEach(Self.limits, id: \.self) { value in
                                Text(value == 0 ? String(localized: "제한 없음") : String(localized: "\(value)번"))
                                    .tag(value)
                            }
                        }
                        Picker("만료", selection: $expiry) {
                            ForEach(Self.expiries, id: \.days) { option in
                                Text(option.label).tag(option.days)
                            }
                        }
                        Toggle("들어오기 전에 승인", isOn: $approval)
                        Button("이 설정으로 새 링크 만들기") { Task { await make() } }
                            .disabled(making)
                    }
                }
            }
            .navigationTitle("\(roomName)에 초대")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func usage(_ invite: RoomInvite) -> String {
        if let max = invite.maxUses { return String(localized: "\(invite.uses)/\(max)번 사용") }
        return String(localized: "\(invite.uses)번 사용")
    }

    private func load() async {
        do {
            if let live = try await RoomAPI.invites(roomId).first(where: { !$0.disabled }) {
                invite = live
            } else {
                invite = try await RoomAPI.invite(roomId)
            }
        } catch {
            failed = error.localizedDescription
        }
    }

    private func make() async {
        making = true
        defer { making = false }
        do {
            invite = try await RoomAPI.invite(
                roomId,
                maxUses: limit == 0 ? nil : limit,
                expiresIn: expiry == 0 ? nil : Int64(expiry) * 86_400,
                approval: approval)
        } catch {
            failed = error.localizedDescription
        }
    }
}

struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }

    private static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
