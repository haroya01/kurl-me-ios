//
//  TranslationViews.swift
//  kurl
//

import SwiftUI

struct NoteTranslationLine: View {
    let noteId: Int64
    let source: Locale.Language
    let phase: ContentTranslations.Phase?
    let translate: () -> Void
    let showOriginal: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            switch phase {
            case .translating:
                Text("번역하는 중…")
            case .shown:
                Text("\(TranslationGate.displayName(source))에서 번역됨")
                Text(verbatim: "·")
                Button("원문 보기", action: showOriginal)
                    .buttonStyle(.borderless)
                    .tint(Palette.link)
                    .accessibilityIdentifier("note.original.\(noteId)")
            case nil:
                Button("번역 보기", action: translate)
                    .buttonStyle(.borderless)
                    .tint(Palette.link)
                    .accessibilityIdentifier("note.translate.\(noteId)")
            }
        }
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}

struct PostTranslationBanner: View {
    let source: Locale.Language
    let phase: ContentTranslations.Phase?
    let translate: () -> Void
    let showOriginal: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "translate")
                .accessibilityHidden(true)
            switch phase {
            case .translating:
                Text("번역하는 중…")
                ProgressView()
                    .controlSize(.mini)
            case .shown:
                Text("\(TranslationGate.displayName(source))에서 번역됨")
                Spacer(minLength: 8)
                Button("원문 보기", action: showOriginal)
                    .buttonStyle(.borderless)
                    .tint(Palette.link)
                    .accessibilityIdentifier("post.original")
            case nil:
                Text("\(TranslationGate.displayName(source))로 쓴 글이에요")
                Spacer(minLength: 8)
                Button("번역 보기", action: translate)
                    .buttonStyle(.borderless)
                    .tint(Palette.link)
                    .accessibilityIdentifier("post.translate")
            }
        }
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
        .padding(.top, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post.translation")
    }
}
