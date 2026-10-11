//
//  NoteFiltersView.swift
//  kurl
//

import SwiftUI

struct NoteFiltersView: View {
    @State private var editing: NoteFilter?
    @State private var adding = false
    @State private var loading = true
    @State private var store = NoteFilterStore.shared

    var body: some View {
        List {
            if store.filters.isEmpty, !loading {
                ContentUnavailableView {
                    Text("키워드 필터가 없어요")
                } description: {
                    Text("보고 싶지 않은 말이 든 노트를 접거나 숨겨요. 내 노트에는 걸리지 않아요.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(store.filters) { filter in
                Button { editing = filter } label: { row(filter) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("noteFilter.row.\(filter.id)")
            }
            .onDelete { offsets in
                let doomed = offsets.map { store.filters[$0] }
                Task {
                    for filter in doomed { try? await store.delete(filter) }
                }
            }
        }
        .navigationTitle("키워드 필터")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("필터 추가")
                    .accessibilityIdentifier("noteFilter.add")
            }
        }
        .sheet(isPresented: $adding) { NoteFilterEditor(filter: nil) }
        .sheet(item: $editing) { NoteFilterEditor(filter: $0) }
        .task {
            await store.reload()
            loading = false
        }
    }

    private func row(_ filter: NoteFilter) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(filter.phrase)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                Text(filter.action == "hide" ? LocalizedStringKey("숨기기") : LocalizedStringKey("접기"))
                    .typeScale(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Palette.chipBg, in: Capsule())
            }
            Text(summary(filter))
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func summary(_ filter: NoteFilter) -> String {
        let places = NoteFilterContext.allCases
            .filter { filter.context.contains($0.rawValue) }
            .map { String(localized: $0.titleResource) }
            .joined(separator: " · ")
        guard let end = filter.expiresAt else { return places }
        return places + " · " + String(localized: "\(end.formatted(.dateTime.month().day().hour().minute()))까지")
    }
}

extension NoteFilterContext {
    var titleResource: LocalizedStringResource {
        switch self {
        case .home: "팔로잉·리스트"
        case .public: "최신·인기·태그"
        case .thread: "답글"
        case .account: "프로필"
        case .notifications: "알림"
        }
    }
}

private enum FilterDuration: Int, CaseIterable, Identifiable {
    case forever = 0
    case thirtyMinutes = 1800
    case hour = 3600
    case sixHours = 21_600
    case twelveHours = 43_200
    case day = 86_400
    case week = 604_800

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .forever: "무기한"
        case .thirtyMinutes: "30분"
        case .hour: "1시간"
        case .sixHours: "6시간"
        case .twelveHours: "12시간"
        case .day: "1일"
        case .week: "7일"
        }
    }
}

struct NoteFilterEditor: View {
    let filter: NoteFilter?

    @State private var phrase: String
    @State private var wholeWord: Bool
    @State private var contexts: Set<NoteFilterContext>
    @State private var hides: Bool
    @State private var duration: FilterDuration = .forever
    @State private var saving = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(filter: NoteFilter?) {
        self.filter = filter
        _phrase = State(initialValue: filter?.phrase ?? "")
        _wholeWord = State(initialValue: filter?.wholeWord ?? false)
        _contexts = State(
            initialValue: filter.map { Set($0.context.compactMap(NoteFilterContext.init(rawValue:))) }
                ?? [.home, .public, .thread])
        _hides = State(initialValue: filter?.action == "hide")
    }

    private var trimmed: String { phrase.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !saving && !trimmed.isEmpty && trimmed.count <= 100 && !contexts.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("키워드나 문구", text: $phrase)
                        .accessibilityIdentifier("noteFilter.phrase")
                    Toggle("단어 전체가 맞을 때만", isOn: $wholeWord)
                } footer: {
                    Text("끄면 \"고양이\"가 \"고양이가\"에도 걸려요. 한국어는 조사가 붙어서 꺼 두는 편이 맞아요.")
                }
                Section("걸리는 곳") {
                    ForEach(NoteFilterContext.allCases) { context in
                        Toggle(context.title, isOn: Binding(
                            get: { contexts.contains(context) },
                            set: { on in
                                if on { contexts.insert(context) } else { contexts.remove(context) }
                            }))
                        .accessibilityIdentifier("noteFilter.context.\(context.rawValue)")
                    }
                }
                Section {
                    Picker("걸리면", selection: $hides) {
                        Text("경고와 함께 접기").tag(false)
                        Text("완전히 숨기기").tag(true)
                    }
                    .accessibilityIdentifier("noteFilter.action")
                    Picker("기간", selection: $duration) {
                        ForEach(FilterDuration.allCases) { Text($0.title).tag($0) }
                    }
                }
                if filter != nil {
                    Section {
                        Button("필터 지우기", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(filter == nil ? LocalizedStringKey("새 필터") : LocalizedStringKey("필터 고치기"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("저장") }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("noteFilter.save")
                }
            }
            .alert("이 필터를 지울까요?", isPresented: $confirmDelete) {
                Button("지우기", role: .destructive) { Task { await delete() } }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let draft = NoteFilterDraft(
            phrase: trimmed, wholeWord: wholeWord,
            context: NoteFilterContext.allCases.filter(contexts.contains).map(\.rawValue),
            action: hides ? "hide" : "warn",
            expiresIn: duration == .forever ? nil : duration.rawValue)
        do {
            try await NoteFilterStore.shared.save(draft, editing: filter?.id)
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "필터를 저장하지 못했어요"))
        }
    }

    private func delete() async {
        guard let filter else { return }
        do {
            try await NoteFilterStore.shared.delete(filter)
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "필터를 지우지 못했어요"))
        }
    }
}
