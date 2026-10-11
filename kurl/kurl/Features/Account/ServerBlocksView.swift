//
//  ServerBlocksView.swift
//  kurl
//

import SwiftUI

/// 설정 > 서버 관리(운영자) — 마스토돈 관리자 도메인 차단. 제한은 그 서버 노트를 인기·태그에서 빼고
/// 팔로우하지 않은 회원에게 알림을 막는다. 정지는 주고받기를 끊고 어디서도 보이지 않게 한다.
/// 정지가 끊은 팔로우와 지운 알림은 해제해도 돌아오지 않아 정지는 한 번 묻는다.
struct ServerBlocksView: View {
    @State private var blocks: [ServerBlock] = []
    @State private var loading = true
    @State private var failed = false
    @State private var adding = false
    @State private var suspending: ServerBlock?

    var body: some View {
        ReadingColumn(spacing: 0) {
            Color.clear.frame(height: 8)
            if loading && blocks.isEmpty {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed && blocks.isEmpty {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await load() } })
                    .padding(.top, 60)
            } else if blocks.isEmpty {
                ContentUnavailableView {
                    Text("차단한 서버가 없어요").bold()
                } description: {
                    Text("다른 서버 전체를 제한하거나 정지할 수 있어요.")
                }
                .padding(.top, 60)
            } else {
                Text("제한하면 그 서버 노트가 인기·태그에서 빠지고, 팔로우하지 않은 회원에게는 알림이 가지 않아요. 정지하면 주고받기를 모두 끊고 그 서버 노트를 어디서도 보이지 않게 해요.")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding(.vertical, 10)
                LazyVStack(spacing: 0) {
                    ForEach(blocks) { block in
                        row(block)
                        if block.id != blocks.last?.id { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("서버 관리")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("서버 차단")
                .accessibilityIdentifier("serverBlocks.add")
            }
        }
        .sheet(isPresented: $adding) {
            ServerBlockSheet { saved in apply(saved) }
        }
        .alert(
            "\(suspending?.domain ?? "")을(를) 정지할까요?",
            isPresented: Binding(get: { suspending != nil }, set: { if !$0 { suspending = nil } })
        ) {
            Button("정지", role: .destructive) {
                if let block = suspending {
                    Task { await change(block, to: .suspend) }
                }
            }
            .accessibilityIdentifier("serverBlocks.confirmSuspend")
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 서버와의 팔로우가 양쪽 모두 끊기고 그 서버에서 온 알림이 지워져요. 해제해도 돌아오지 않아요.")
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            blocks = try await FederationAPI.serverBlocks()
        } catch {
            failed = true
        }
        loading = false
    }

    private func apply(_ saved: ServerBlock) {
        var next = blocks.filter { $0.domain != saved.domain }
        next.append(saved)
        next.sort { $0.domain < $1.domain }
        blocks = next
    }

    private func change(_ block: ServerBlock, to severity: ServerBlock.Severity) async {
        do {
            apply(try await FederationAPI.blockServer(block.domain, severity: severity, reason: block.reason))
        } catch {
            ToastCenter.shared.show(String(localized: "바꾸지 못했어요"))
        }
    }

    private func lift(_ block: ServerBlock) async {
        do {
            try await FederationAPI.unblockServer(block.domain)
            withAnimation(.snappy(duration: 0.2)) { blocks.removeAll { $0.id == block.id } }
            ToastCenter.shared.show(String(localized: "\(block.domain) 차단을 해제했어요"))
        } catch {
            ToastCenter.shared.show(String(localized: "해제하지 못했어요"))
        }
    }

    private func row(_ block: ServerBlock) -> some View {
        HStack(spacing: 12) {
            Image(systemName: block.severity == .suspend ? "nosign" : "speaker.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(block.severity == .suspend ? Palette.danger : Palette.secondary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: block.domain)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(ServerBlockSheet.title(block.severity))
                        .fontWeight(.semibold)
                        .foregroundStyle(block.severity == .suspend ? Palette.danger : Palette.ink)
                    if let reason = block.reason {
                        Text(verbatim: reason)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                .typeScale(.meta)
            }
            Spacer(minLength: 8)
            Menu {
                if block.severity == .limit {
                    Button("정지로 올리기", systemImage: "nosign", role: .destructive) { suspending = block }
                } else {
                    Button("제한으로 낮추기", systemImage: "speaker.slash") {
                        Task { await change(block, to: .limit) }
                    }
                }
                Button("차단 해제", systemImage: "arrow.uturn.backward") {
                    Task { await lift(block) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("\(block.domain) 관리"))
            .accessibilityIdentifier("serverBlocks.menu.\(block.domain)")
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("serverBlocks.row.\(block.domain)")
    }
}

/// 새 서버 차단 — 서버·단계·사유(운영자만 봐요). 정지는 시트 안에서 한 번 묻는다.
struct ServerBlockSheet: View {
    let onSaved: (ServerBlock) -> Void
    @State private var domain = ""
    @State private var severity: ServerBlock.Severity = .limit
    @State private var reason = ""
    @State private var saving = false
    @State private var confirmSuspend = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    static func title(_ severity: ServerBlock.Severity) -> LocalizedStringKey {
        severity == .suspend ? "정지" : "제한"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("mastodon.example", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("serverBlocks.domain")
                    Picker("단계", selection: $severity) {
                        ForEach(ServerBlock.Severity.allCases, id: \.self) { level in
                            Text(Self.title(level)).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("serverBlocks.severity")
                } footer: {
                    Text(severity == .suspend
                        ? "주고받기를 모두 끊고, 그 서버 노트를 어디서도 보이지 않게 해요."
                        : "그 서버 노트가 인기·태그에서 빠지고, 팔로우하지 않은 회원에게는 알림이 가지 않아요.")
                }
                Section {
                    TextField("사유 (선택, 운영자만 봐요)", text: $reason, axis: .vertical)
                        .accessibilityIdentifier("serverBlocks.reason")
                }
            }
            .navigationTitle("서버 차단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("차단") {
                        if severity == .suspend { confirmSuspend = true } else { Task { await save() } }
                    }
                    .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                    .accessibilityIdentifier("serverBlocks.save")
                }
            }
            .alert("정지할까요?", isPresented: $confirmSuspend) {
                Button("정지", role: .destructive) { Task { await save() } }
                    .accessibilityIdentifier("serverBlocks.confirmSuspend")
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 서버와의 팔로우가 양쪽 모두 끊기고 그 서버에서 온 알림이 지워져요. 해제해도 돌아오지 않아요.")
            }
            .alert(
                "차단하지 못했어요",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let saved = try await FederationAPI.blockServer(
                domain.trimmingCharacters(in: .whitespaces).lowercased(),
                severity: severity,
                reason: note.isEmpty ? nil : note)
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = String(localized: "서버 이름을 확인해 주세요. mastodon.example처럼 적어요.")
        }
    }
}
