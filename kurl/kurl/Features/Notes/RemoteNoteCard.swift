//
//  RemoteNoteCard.swift
//  kurl
//

import SwiftUI

struct RemoteNoteCard: View {
    let noteId: Int64
    let shape: RemoteNoteShape
    let summary: String
    let picture: NoteMedia?
    var full = false
    @State private var opened: LegalLink?

    static func picture(in note: Note) -> NoteMedia? {
        guard note.contentWarning == nil, note.sensitive != true else { return nil }
        return note.media.first { $0.contentType.hasPrefix("image/") }
    }

    static func ratio(_ kind: RemoteNoteShape.Kind?) -> CGFloat {
        kind == .video ? 16.0 / 9.0 : 1.91
    }

    static func spokenLabel(_ shape: RemoteNoteShape) -> String {
        [shape.title, String(localized: "원문에서 보기"), shape.host].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        if let url = shape.original {
            Button {
                opened = LegalLink(url: url)
            } label: {
                card
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.spokenLabel(shape)))
            .accessibilityAddTraits(.isLink)
            .accessibilityIdentifier("note.remoteCard.\(noteId)")
            .sheet(item: $opened) { SafariView(url: $0.url).ignoresSafeArea() }
        } else {
            card
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("note.remoteCard.\(noteId)")
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let picture {
                pictureView(picture)
            }
            VStack(alignment: .leading, spacing: 4) {
                if shape.kind == .page, let community = shape.community {
                    Text(verbatim: community)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let title = shape.title {
                    Text(verbatim: title)
                        .typeScale(full ? .noteFocus : .note)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(full ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !summary.isEmpty {
                    Text(verbatim: summary)
                        .typeScale(.note)
                        .foregroundStyle(full ? Palette.ink : Palette.secondary)
                        .lineLimit(full ? nil : 3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if shape.original != nil {
                    RemoteOriginalLabel(title: "원문에서 보기", host: shape.host)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).stroke(Palette.hairlineStrong, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
    }

    private func pictureView(_ media: NoteMedia) -> some View {
        Palette.hairline
            .aspectRatio(Self.ratio(shape.kind), contentMode: .fit)
            .overlay {
                RemoteImage(url: URL(string: media.url), maxPixel: 900) { phase in
                    if case .success(let loaded) = phase {
                        loaded.resizable().scaledToFill()
                    }
                }
            }
            .overlay {
                if shape.kind == .video { NotePlayMark() }
            }
            .clipped()
            .overlay(alignment: .bottom) { Hairline() }
            .accessibilityHidden(true)
    }
}

struct RemoteOriginalLabel: View {
    let title: LocalizedStringResource
    var host: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .foregroundStyle(Palette.ink)
                .fixedSize()
            if let host {
                Text(verbatim: "· \(host)")
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.faint)
                .accessibilityHidden(true)
        }
        .typeScale(.meta)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [String(localized: title), host].compactMap { $0 }.joined(separator: ", ")))
    }
}
