//
//  ProfileTabs.swift
//  kurl
//

import Observation
import SwiftUI

@MainActor
@Observable
final class ProfilePager<Item: Identifiable & Hashable> {
    private(set) var items: [Item] = []
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var isLoadingMore = false

    private var page = 0
    private var hasNext = true
    private var epoch = 0
    private let fetch: (Int) async throws -> (items: [Item], hasNext: Bool)

    init(fetch: @escaping (Int) async throws -> (items: [Item], hasNext: Bool)) {
        self.fetch = fetch
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty { phase = .loading }
        do {
            let head = try await fetch(0)
            guard myEpoch == epoch else { return }
            page = 0
            items = head.items
            hasNext = head.hasNext
            phase = .loaded(true)
        } catch {
            guard myEpoch == epoch else { return }
            if items.isEmpty {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            } else {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
        }
    }

    func loadMoreIfNeeded(current item: Item) async {
        guard hasNext, !isLoadingMore, items.last?.id == item.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let myEpoch = epoch
        guard let next = try? await fetch(page + 1), myEpoch == epoch else { return }
        let seen = Set(items.map(\.id))
        page += 1
        hasNext = next.hasNext
        items.append(contentsOf: next.items.filter { !seen.contains($0.id) })
    }

    func replace(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func remove(where matches: (Item) -> Bool) {
        withAnimation(.snappy(duration: 0.25)) { items.removeAll(where: matches) }
    }
}

extension ProfilePager where Item == ProfileReplies.Item {
    static func replies(of username: String) -> ProfilePager {
        ProfilePager { page in
            let feed = try await NoteAPI.profileReplies(username, page: page)
            return (feed.items, feed.hasNext)
        }
    }
}

extension ProfilePager where Item == ProfileMedia.Item {
    static func media(of username: String) -> ProfilePager {
        ProfilePager { page in
            let feed = try await NoteAPI.profileMedia(username, page: page)
            return (feed.items, feed.hasNext)
        }
    }
}

enum ReplyHeader: Hashable {
    case to(ProfileReplies.ReplyContext)
    case unavailable

    init(_ context: ProfileReplies.ReplyContext?) {
        self = context.map(ReplyHeader.to) ?? .unavailable
    }
}

struct ReplyHeaderLine: View {
    let header: ReplyHeader

    var body: some View {
        switch header {
        case .to(let context):
            NavigationLink(value: Route.note(id: context.id)) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    glyph
                    Text("@\(context.author.username) 님에게 답글")
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .fixedSize()
                    Text(context.contentWarning ?? context.excerpt ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.reply.context.\(context.id)")
        case .unavailable:
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                glyph
                Text("원래 글을 볼 수 없어요")
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.reply.context.unavailable")
        }
    }

    private var glyph: some View {
        Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 36, alignment: .trailing)
            .accessibilityHidden(true)
    }
}

struct ProfileMediaCell: View {
    let item: ProfileMedia.Item

    var body: some View {
        NavigationLink(value: Route.note(id: item.noteId)) {
            thumbnail
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("profile.media.\(item.noteId)")
    }

    private var thumbnail: some View {
        Color.clear
            .overlay {
                RemoteImage(url: URL(string: item.media.url), maxPixel: 400) { phase in
                    Palette.hairline.overlay {
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .overlay {
                if item.sensitive {
                    ZStack {
                        Rectangle().fill(.ultraThickMaterial)
                        Image(systemName: "eye.slash")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.mediaCount > 1 {
                    Label("\(item.mediaCount)", systemImage: "square.on.square")
                        .labelStyle(.titleAndIcon)
                        .typeScale(.footnote)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var accessibilityText: Text {
        if item.sensitive {
            return Text("민감한 사진 \(item.mediaCount)장")
        }
        if let alt = item.media.altText, !alt.isEmpty {
            return Text("\(alt), 사진 \(item.mediaCount)장")
        }
        return Text("사진 \(item.mediaCount)장")
    }
}
