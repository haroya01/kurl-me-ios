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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kind = EditorLinkKind.link
    @State private var text: String
    @State private var address: String
    @State private var shortens = false
    @State private var busy = false
    @State private var invalidAddress = false
    @State private var shortenFailed = false
    @State private var contentHeight: CGFloat = 320
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
    private var motion: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }

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
                                Task { @MainActor in address = value }
                            }
                            .labelStyle(.titleOnly)
                        } else {
                            Button {
                                address = ""
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
                } header: {
                    Text("주소")
                } footer: {
                    if invalidAddress {
                        Text("올바른 주소가 아니에요")
                            .foregroundStyle(Palette.danger)
                            .accessibilityIdentifier("editor-link-invalid")
                    }
                }
                if kind == .card, let url, let block = DraftPreviewBlocks.embed(url) {
                    Section {
                        BlockView(block: block)
                            .frame(maxWidth: video ? 256 : .infinity)
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("editor-link-preview")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if kind == .link {
                    Section {
                        TextField("표시 텍스트", text: $text, prompt: Text("비우면 주소가 보여요"))
                            .focused($focus, equals: .text)
                            .submitLabel(.done)
                            .onSubmit(submit)
                            .accessibilityIdentifier("editor-link-text")
                    } header: {
                        Text("표시 텍스트")
                    }
                    Section {
                        Toggle("kurl 단축 주소로", isOn: $shortens)
                            .tint(Palette.accentFill)
                            .accessibilityIdentifier("editor-link-shorten")
                    } footer: {
                        if shortenFailed {
                            Text("단축 주소를 만들지 못했어요")
                                .foregroundStyle(Palette.danger)
                                .accessibilityIdentifier("editor-link-shorten-failed")
                        }
                    }
                }
            }
            .animation(motion, value: kind)
            .contentMargins(.top, 8, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top
            } action: { _, height in
                withAnimation(motion) { contentHeight = height }
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
                            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("editor-link-submit")
                    }
                }
            }
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .onChange(of: address) {
            invalidAddress = false
            shortenFailed = false
        }
        .onChange(of: shortens) { shortenFailed = false }
        .onAppear {
            if request.target.map({ $0.editing || !$0.shownText.isEmpty }) ?? false { focus = .address }
        }
    }

    private func submit() {
        guard !busy else { return }
        guard let url else {
            invalidAddress = true
            focus = .address
            return
        }
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .link, shortens else {
            finish(EditorLinkResult(kind: kind, text: kind == .link ? label : "", url: url))
            return
        }
        busy = true
        Task {
            let short = await shorten(url)
            busy = false
            guard let short else { shortenFailed = true; return }
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
