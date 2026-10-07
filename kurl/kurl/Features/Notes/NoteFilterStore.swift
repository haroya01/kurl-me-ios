//
//  NoteFilterStore.swift
//  kurl
//

import Foundation
import Observation
import SwiftUI

enum NoteFilterContext: String, CaseIterable, Identifiable {
    case home, `public`, thread, account, notifications

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "팔로잉·리스트"
        case .public: "모든 노트·인기·태그"
        case .thread: "답글"
        case .account: "프로필"
        case .notifications: "알림"
        }
    }
}

enum NoteFilterVerdict: Equatable {
    case hide
    case warn([String])
}

@MainActor
@Observable
final class NoteFilterStore {
    static let shared = NoteFilterStore()

    private(set) var filters: [NoteFilter] = []
    @ObservationIgnored private var patterns: [Int64: NSRegularExpression] = [:]

    private init() {}

    func reload() async {
        guard AuthStore.shared.isSignedIn else {
            filters = []
            return
        }
        if let loaded = try? await NoteAPI.filters() { filters = loaded }
    }

    func save(_ draft: NoteFilterDraft, editing id: Int64?) async throws {
        let saved =
            if let id {
                try await NoteAPI.updateFilter(id: id, draft)
            } else {
                try await NoteAPI.createFilter(draft)
            }
        patterns[saved.id] = nil
        if let index = filters.firstIndex(where: { $0.id == saved.id }) {
            filters[index] = saved
        } else {
            filters.insert(saved, at: 0)
        }
    }

    func delete(_ filter: NoteFilter) async throws {
        try await NoteAPI.deleteFilter(id: filter.id)
        filters.removeAll { $0.id == filter.id }
    }

    /// 마스토돈처럼 내 노트에는 걸지 않는다. 숨기기가 하나라도 맞으면 숨기고, 아니면 맞은 경고 문구들.
    func verdict(for note: Note, in context: NoteFilterContext) -> NoteFilterVerdict? {
        guard !filters.isEmpty, note.author.id != AuthStore.shared.me?.id else { return nil }
        let text = [
            note.body, note.contentWarning ?? "",
            (note.poll?.options.map(\.title) ?? []).joined(separator: "\n"),
            note.media.compactMap(\.altText).joined(separator: "\n"),
        ].joined(separator: "\n")
        return verdict(for: text, in: context)
    }

    func verdict(for text: String, in context: NoteFilterContext) -> NoteFilterVerdict? {
        var warned: [String] = []
        let now = Date()
        for filter in filters where filter.context.contains(context.rawValue) {
            if let end = filter.expiresAt, end <= now { continue }
            guard matches(filter, text) else { continue }
            if filter.action == "hide" { return .hide }
            warned.append(filter.phrase)
        }
        return warned.isEmpty ? nil : .warn(warned)
    }

    private func matches(_ filter: NoteFilter, _ text: String) -> Bool {
        let pattern: NSRegularExpression
        if let cached = patterns[filter.id] {
            pattern = cached
        } else {
            let escaped = NSRegularExpression.escapedPattern(for: filter.phrase)
            let source = filter.wholeWord ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])" : escaped
            guard let compiled = try? NSRegularExpression(pattern: source, options: [.caseInsensitive])
            else { return false }
            patterns[filter.id] = compiled
            pattern = compiled
        }
        return pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

private struct NoteFilterContextKey: EnvironmentKey {
    static let defaultValue: NoteFilterContext? = nil
}

extension EnvironmentValues {
    var noteFilterContext: NoteFilterContext? {
        get { self[NoteFilterContextKey.self] }
        set { self[NoteFilterContextKey.self] = newValue }
    }
}
