//
//  CountryBlockSheet.swift
//  kurl
//

import SwiftUI

struct Country: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

enum Countries {
    static let all: [Country] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        .compactMap { code in
            Locale.current.localizedString(forRegionCode: code).map { Country(code: code.uppercased(), name: $0) }
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

    static func name(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    static func summary(_ codes: [String]) -> String {
        switch codes.count {
        case 0: String(localized: "없음")
        case 1: name(for: codes[0])
        default: String(localized: "\(codes.count)개국")
        }
    }
}

struct CountryBlockSheet: View {
    let onDone: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var query = ""
    @State private var toggles = 0

    init(selected: [String], onDone: @escaping ([String]) -> Void) {
        _selected = State(initialValue: Set(selected.map { $0.uppercased() }))
        self.onDone = onDone
    }

    private var chosen: [Country] {
        Countries.all.filter { selected.contains($0.code) }
    }

    private var filtered: [Country] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Countries.all }
        return Countries.all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if query.isEmpty {
                        ForEach(chosen) { row($0) }
                    }
                } header: {
                    if query.isEmpty, !selected.isEmpty {
                        Text("고른 국가")
                    }
                } footer: {
                    if query.isEmpty {
                        Text("이 나라에서는 제목만 보여요. VPN을 쓰면 막지 못해요.")
                    }
                }
                Section {
                    ForEach(filtered) { row($0) }
                }
            }
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("국가 검색"))
            .sensoryFeedback(.selection, trigger: toggles)
            .navigationTitle("국가 제한")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        onDone(selected.sorted())
                        dismiss()
                    }
                    .accessibilityIdentifier("countries.done")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ country: Country) -> some View {
        let isOn = selected.contains(country.code)
        return Button {
            if isOn { selected.remove(country.code) } else { selected.insert(country.code) }
            toggles += 1
        } label: {
            HStack(spacing: 10) {
                Text(country.name)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(verbatim: country.code)
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .opacity(isOn ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("country.\(country.code)")
    }
}
