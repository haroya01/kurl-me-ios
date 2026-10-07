//
//  DataExportView.swift
//  kurl
//

import SwiftUI
import UIKit

/// 설정 > 데이터 내보내기 — 마스토돈과 같은 CSV 파일. 다른 마스토돈 서버의 가져오기가 그대로 읽는다.
/// 줄을 누르면 내려받아 공유 시트(파일에 저장·AirDrop 등)를 연다.
struct DataExportView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case following, blocks, mutes, domainBlocks = "domain-blocks", bookmarks, lists

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .following: "팔로우"
            case .blocks: "차단한 계정"
            case .mutes: "뮤트한 계정"
            case .domainBlocks: "차단한 서버"
            case .bookmarks: "북마크"
            case .lists: "리스트"
            }
        }

        var icon: String {
            switch self {
            case .following: "person.2"
            case .blocks: "hand.raised"
            case .mutes: "speaker.slash"
            case .domainBlocks: "server.rack"
            case .bookmarks: "bookmark"
            case .lists: "list.bullet"
            }
        }

        var filename: String {
            switch self {
            case .following: "following_accounts.csv"
            case .blocks: "blocked_accounts.csv"
            case .mutes: "muted_accounts.csv"
            case .domainBlocks: "blocked_domains.csv"
            case .bookmarks: "bookmarks.csv"
            case .lists: "lists.csv"
            }
        }
    }

    private struct Ready: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @State private var busy: Kind?
    @State private var ready: Ready?

    var body: some View {
        ReadingColumn(spacing: 0) {
            Text("마스토돈과 같은 CSV 파일이라, 다른 서버의 가져오기에 그대로 올릴 수 있어요.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 16)
                .padding(.bottom, 6)
            ForEach(Kind.allCases) { kind in
                row(kind)
                if kind != Kind.allCases.last { Hairline() }
            }
        }
        .navigationTitle("데이터 내보내기")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .sheet(item: $ready) { file in
            ActivitySheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func row(_ kind: Kind) -> some View {
        Button {
            download(kind)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.accentMarker)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: kind.filename)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                if busy == kind {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
        .accessibilityIdentifier("export.\(kind.rawValue)")
    }

    private func download(_ kind: Kind) {
        busy = kind
        Task {
            defer { busy = nil }
            do {
                let data = try await APIClient.shared.getAuthenticatedData("/users/me/exports/\(kind.rawValue)")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(kind.filename)
                try data.write(to: url, options: .atomic)
                ready = Ready(url: url)
            } catch {
                ToastCenter.shared.show(String(localized: "내보내지 못했어요"))
            }
        }
    }
}

/// 시스템 공유 시트 — 내려받은 파일을 파일 앱·AirDrop·메일로.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
