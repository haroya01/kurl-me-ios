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
                original
            case .shown:
                Text("\(TranslationGate.displayName(source))에서 번역됨")
                original
            case nil:
                Button("번역 보기", action: translate)
                    .buttonStyle(.borderless)
                    .tint(Palette.ink)
                    .accessibilityIdentifier("note.translate.\(noteId)")
            }
        }
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var original: some View {
        Text(verbatim: "·")
        Button("원문 보기", action: showOriginal)
            .buttonStyle(.borderless)
            .tint(Palette.ink)
            .accessibilityIdentifier("note.original.\(noteId)")
    }
}
