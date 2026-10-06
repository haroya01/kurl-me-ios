//
//  NoteFeedChoice.swift
//  kurl
//

import Observation
import SwiftUI

enum NoteFeedKind: String, CaseIterable, Identifiable {
    case everyone
    case following
    case trending

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .everyone: "노트"
        case .following: "팔로잉"
        case .trending: "인기"
        }
    }

    var menuLabel: LocalizedStringKey {
        switch self {
        case .everyone: "모든 노트"
        case .following: "팔로잉"
        case .trending: "인기"
        }
    }

    var symbol: String {
        switch self {
        case .everyone: "text.bubble"
        case .following: "person.2"
        case .trending: "flame"
        }
    }
}

@MainActor
@Observable
final class NoteFeedChoice {
    static let shared = NoteFeedChoice()

    private static let key = "notes.feed"

    var kind: NoteFeedKind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: Self.key) }
    }

    private init() {
        let saved = Config.useMocks ? nil : UserDefaults.standard.string(forKey: Self.key)
        kind = saved.flatMap(NoteFeedKind.init) ?? .everyone
    }
}

struct NoteFeedPicker: View {
    @Bindable var choice = NoteFeedChoice.shared

    var body: some View {
        Picker("노트 피드", selection: $choice.kind) {
            ForEach(NoteFeedKind.allCases) { kind in
                Label(kind.menuLabel, systemImage: kind.symbol).tag(kind)
            }
        }
        .pickerStyle(.inline)
    }
}
