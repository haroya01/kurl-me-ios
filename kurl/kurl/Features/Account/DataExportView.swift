//
//  DataExportView.swift
//  kurl
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 설정 > 가져오기·내보내기 — 마스토돈과 같은 CSV 파일. 내보낸 파일은 다른 마스토돈 서버의 가져오기가 그대로
/// 읽고, 다른 서버에서 내보낸 파일은 여기서 가져온다(합치기 — 지금 것은 그대로 두고 더한다). 가져오기는 서버가 뒤에서
/// 한 줄씩 적용하므로 진행을 보여 주며 끝날 때까지 다시 읽는다.
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
    @State private var importing: Kind?
    @State private var pickingFor: Kind?
    @State private var imports: [AccountImport] = []

    var body: some View {
        ReadingColumn(spacing: 0) {
            RailHeading("내보내기")
                .padding(.top, 24)
                .padding(.bottom, 4)
            Text("마스토돈과 같은 CSV 파일이라, 다른 서버의 가져오기에 그대로 올릴 수 있어요.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 6)
            ForEach(Kind.allCases) { kind in
                row(kind)
                if kind != Kind.allCases.last { Hairline() }
            }

            RailHeading("가져오기")
                .padding(.top, 28)
                .padding(.bottom, 4)
            Text("다른 마스토돈 서버에서 내보낸 파일을 올리면 지금 것에 더해요. 이 서버 회원과 다른 서버 계정 팔로우, 이 서버 회원 차단·뮤트·리스트, 차단한 서버, 북마크를 옮길 수 있어요.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 6)
            // 내보내기 줄과 같은 Kind를 쓰므로 묶음을 나눠 정체성이 겹치지 않게 한다.
            VStack(spacing: 0) {
                ForEach(Kind.allCases) { kind in
                    importRow(kind)
                    if kind != Kind.allCases.last { Hairline() }
                }
            }
            if !imports.isEmpty {
                RailHeading("최근 가져오기")
                    .padding(.top, 28)
                    .padding(.bottom, 4)
                ForEach(imports) { item in
                    progressRow(item)
                    if item.id != imports.last?.id { Hairline() }
                }
            }
        }
        .navigationTitle("가져오기·내보내기")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .sheet(item: $ready) { file in
            ActivitySheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: Binding(get: { pickingFor != nil }, set: { if !$0 { pickingFor = nil } }),
            allowedContentTypes: [.commaSeparatedText, .plainText, .text]
        ) { result in
            guard let kind = pickingFor else { return }
            pickingFor = nil
            if case let .success(url) = result { upload(kind, from: url) }
        }
        // 진행 중인 가져오기가 있는 동안 3초마다 다시 읽는다 — 끝나면 멈춘다.
        .task(id: imports.contains { !$0.finished }) {
            await reloadImports()
            while !Task.isCancelled, imports.contains(where: { !$0.finished }) {
                try? await Task.sleep(for: .seconds(3))
                await reloadImports()
            }
        }
    }

    private func importRow(_ kind: Kind) -> some View {
        Button {
            pickingFor = kind
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.accentMarker)
                    .frame(width: 22)
                Text(kind.title)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if importing == kind {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(importing != nil || imports.contains { !$0.finished })
        .accessibilityIdentifier("import.\(kind.rawValue)")
    }

    private func progressRow(_ item: AccountImport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.title(of: item.kind))
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if item.finished {
                    Text("끝남")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
            }
            if !item.finished {
                ProgressView(value: Double(item.processed), total: Double(max(item.total, 1)))
                    .tint(Palette.accent)
            }
            Text("\(item.total)줄 중 \(item.imported)줄 가져옴 · 실패 \(item.failed)줄")
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("import.progress.\(item.id)")
    }

    private static func title(of kind: String) -> LocalizedStringKey {
        switch kind {
        case "FOLLOWING": "팔로우"
        case "BLOCKS": "차단한 계정"
        case "MUTES": "뮤트한 계정"
        case "DOMAIN_BLOCKS": "차단한 서버"
        case "BOOKMARKS": "북마크"
        default: "리스트"
        }
    }

    private func reloadImports() async {
        if let recent = try? await AccountImportAPI.recent() {
            withAnimation(.snappy(duration: 0.2)) { imports = recent }
        }
    }

    private func upload(_ kind: Kind, from url: URL) {
        importing = kind
        Task {
            defer { importing = nil }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let csv = String(data: data, encoding: .utf8) else {
                ToastCenter.shared.show(String(localized: "파일을 읽지 못했어요"))
                return
            }
            do {
                let started = try await AccountImportAPI.start(kind: kind.rawValue, csv: csv)
                withAnimation(.snappy(duration: 0.2)) { imports.insert(started, at: 0) }
                ToastCenter.shared.show(String(localized: "\(started.total)줄을 가져오는 중이에요"))
            } catch let error as APIError where error.statusCode == 409 {
                ToastCenter.shared.show(String(localized: "앞의 가져오기가 끝나면 다시 해 주세요"))
            } catch {
                ToastCenter.shared.show(String(localized: "가져오지 못했어요"))
            }
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
