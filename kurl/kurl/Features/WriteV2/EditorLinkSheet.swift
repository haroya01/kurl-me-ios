//
//  EditorLinkSheet.swift
//  kurl — WriteV2
//

import SwiftUI

struct EditorLinkRequest: Identifiable {
    let id = UUID()
    let target: EditorLinkTarget?
}

enum EditorLinkKind: Hashable {
    case link, card
}

struct EditorLinkResult: Equatable {
    let kind: EditorLinkKind
    let text: String
    let url: String
}

struct EditorLinkSheet: View {
    let request: EditorLinkRequest
    let shorten: (String) async -> String?
    let onSubmit: (EditorLinkResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind = EditorLinkKind.link
    @State private var text: String
    @State private var address: String
    @State private var pasted: String?
    @State private var shortens = false
    @State private var busy = false
    @State private var failed = false
    @FocusState private var focus: Field?

    private enum Field { case text, address }

    init(
        request: EditorLinkRequest,
        shorten: @escaping (String) async -> String?,
        onSubmit: @escaping (EditorLinkResult) -> Void
    ) {
        self.request = request
        self.shorten = shorten
        self.onSubmit = onSubmit
        _text = State(initialValue: request.target?.shownText ?? "")
        _address = State(initialValue: request.target?.url ?? "")
    }

    private var editing: Bool { request.target?.editing ?? false }
    private var canPickCard: Bool { request.target?.canPickCard ?? true }
    private var url: String? { Self.normalized(address) }
    private var video: Bool { url.map { WriteV2VideoDetect.isVideoURL($0) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                if canPickCard {
                    Section {
                        Picker("링크 모양 고르기", selection: $kind) {
                            Text("링크").tag(EditorLinkKind.link)
                            Text(video ? "동영상" : "카드").tag(EditorLinkKind.card)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("editor-link-kind")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    if kind == .link {
                        row("표시 텍스트") {
                            TextField("표시 텍스트", text: $text, prompt: Text("비우면 주소가 보여요"))
                                .focused($focus, equals: .text)
                                .submitLabel(.next)
                                .onSubmit { focus = .address }
                                .accessibilityIdentifier("editor-link-text")
                        }
                    }
                    row("주소") {
                        HStack(spacing: 8) {
                            TextField("주소", text: $address, prompt: Text(verbatim: "https://…"))
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .address)
                                .submitLabel(.done)
                                .onSubmit(submit)
                                .accessibilityIdentifier("editor-link-address")
                            if address.isEmpty {
                                PasteButton(payloadType: String.self) { strings in
                                    guard let first = strings.first else { return }
                                    let value = first.trimmingCharacters(in: .whitespacesAndNewlines)
                                    Task { @MainActor in
                                        address = value
                                        pasted = value
                                    }
                                }
                                .labelStyle(.iconOnly)
                                .buttonBorderShape(.circle)
                                .controlSize(.small)
                            } else {
                                Button {
                                    address = ""
                                    pasted = nil
                                    focus = .address
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("지우기"))
                                .accessibilityIdentifier("editor-link-clear")
                            }
                        }
                    }
                } footer: {
                    if let pasted, pasted == address {
                        Text("클립보드에서 가져왔어요")
                            .accessibilityIdentifier("editor-link-pasted")
                    }
                }
                if kind == .card, let url, let block = DraftPreviewBlocks.embed(url) {
                    Section {
                        BlockView(block: block)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("editor-link-preview")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if kind == .link {
                    Section {
                        Toggle("kurl 단축 주소로", isOn: $shortens)
                            .tint(Palette.accentFill)
                            .accessibilityIdentifier("editor-link-shorten")
                    } footer: {
                        if failed {
                            Text("단축 주소를 만들지 못했어요")
                                .foregroundStyle(Palette.danger)
                                .accessibilityIdentifier("editor-link-shorten-failed")
                        }
                    }
                }
            }
            .navigationTitle(editing ? "링크 고치기" : "링크 넣기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button(editing ? "저장" : "넣기", action: submit)
                            .font(.body.weight(.semibold))
                            .disabled(url == nil)
                            .accessibilityIdentifier("editor-link-submit")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: address) { failed = false }
        .onChange(of: shortens) { failed = false }
        .onAppear { focus = .address }
    }

    private func row(_ label: LocalizedStringKey, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            field()
        }
    }

    private func submit() {
        guard let url, !busy else { return }
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .link, shortens else {
            finish(EditorLinkResult(kind: kind, text: kind == .link ? label : "", url: url))
            return
        }
        busy = true
        Task {
            let short = await shorten(url)
            busy = false
            guard let short else { failed = true; return }
            finish(EditorLinkResult(kind: .link, text: label, url: short))
        }
    }

    private func finish(_ result: EditorLinkResult) {
        onSubmit(result)
        dismiss()
    }

    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let comps = URLComponents(string: candidate),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = comps.host, host.contains(".") || host == "localhost"
        else { return nil }
        return candidate
    }
}
