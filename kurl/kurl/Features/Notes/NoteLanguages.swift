//
//  NoteLanguages.swift
//  kurl
//

import SwiftUI

/// 노트에 고를 수 있는 언어 — 이름은 마스토돈처럼 그 언어 자신의 글자로 쓴다.
enum NoteLanguages {
    struct Language: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }

    static let all: [Language] = [
        .init(code: "ko", name: "한국어"),
        .init(code: "ja", name: "日本語"),
        .init(code: "en", name: "English"),
        .init(code: "zh", name: "中文"),
        .init(code: "vi", name: "Tiếng Việt"),
        .init(code: "hi", name: "हिन्दी"),
        .init(code: "es", name: "Español"),
        .init(code: "fr", name: "Français"),
        .init(code: "de", name: "Deutsch"),
        .init(code: "pt", name: "Português"),
        .init(code: "id", name: "Bahasa Indonesia"),
        .init(code: "th", name: "ไทย"),
    ]

    private static let key = "notes.postingLanguage"

    static func name(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// 지난번에 고른 언어, 없으면 기기 언어, 목록에 없으면 한국어.
    static var posting: String {
        if let saved = UserDefaults.standard.string(forKey: key), all.contains(where: { $0.code == saved }) {
            return saved
        }
        let device = Locale.current.language.languageCode?.identifier ?? "ko"
        return all.contains(where: { $0.code == device }) ? device : "ko"
    }

    static func remember(_ code: String) {
        UserDefaults.standard.set(code, forKey: key)
    }
}

/// 설정 > 노트 > 보이는 노트 언어 — 마스토돈의 언어 거르기. 모든 노트·인기에만 적용된다.
struct NoteLanguagesView: View {
    @State private var preferences = NoteFeedPreferences.shared
    @State private var chosen: Set<String> = []
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                Button {
                    chosen = []
                    save()
                } label: {
                    row(name: String(localized: "모든 언어"), on: chosen.isEmpty)
                }
                .accessibilityIdentifier("noteLanguages.all")
            }
            Section {
                ForEach(NoteLanguages.all) { language in
                    Button {
                        if chosen.contains(language.code) {
                            chosen.remove(language.code)
                        } else {
                            chosen.insert(language.code)
                        }
                        save()
                    } label: {
                        row(name: language.name, on: chosen.contains(language.code))
                    }
                    .accessibilityIdentifier("noteLanguages.\(language.code)")
                }
            } footer: {
                Text("모든 노트와 인기에 고른 언어의 노트만 보여요. 언어를 정하지 않은 노트와 팔로잉·리스트는 그대로예요.")
            }
        }
        .navigationTitle("보이는 노트 언어")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .task {
            await preferences.hydrateIfNeeded()
            if !loaded {
                chosen = Set(preferences.languages)
                loaded = true
            }
        }
    }

    private func row(name: String, on: Bool) -> some View {
        HStack {
            Text(verbatim: name)
                .foregroundStyle(Palette.ink)
            Spacer()
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.link)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func save() {
        let codes = NoteLanguages.all.map(\.code).filter { chosen.contains($0) }
        Task { await preferences.setLanguages(codes) }
    }
}
