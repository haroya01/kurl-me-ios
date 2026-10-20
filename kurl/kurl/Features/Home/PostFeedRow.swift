//
//  PostFeedRow.swift
//  kurl
//

import SwiftUI

struct PostFeedRow: View {
    let post: FeedItem

    @State private var likes = LikeStore.shared
    @State private var bookmarks = BookmarkStore.shared
    @State private var likeTaps = 0
    @State private var likedAtStart: Bool?
    @State private var showLogin = false
    @State private var bookmarkTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .callout) private var nameCapCenter: CGFloat = 9
    @ScaledMetric(relativeTo: .callout) private var nameCapHalf: CGFloat = 5.3

    private static let actionBox: CGFloat = 22
    private var unit: CGFloat { min(scale, 1.8) }
    private var route: Route { .post(username: post.author.username, slug: post.slug) }
    private var liked: Bool { likes.contains(username: post.author.username, slug: post.slug) }
    private var likeCount: Int64 {
        let start = likedAtStart ?? liked
        return max(post.likeCount + (liked && !start ? 1 : 0) - (!liked && start ? 1 : 0), 0)
    }
    private var bookmarked: Bool { bookmarks.contains(post.id) }

    var quoted: QuotedPost {
        QuotedPost(
            id: post.id, title: post.title, slug: post.slug, authorUsername: post.author.username,
            audience: post.audience, locked: post.locked, regionRestricted: post.regionRestricted)
    }

    var body: some View {
        HStack(alignment: .noteNameLine, spacing: 12) {
            NavigationLink(value: Route.author(username: post.author.username)) {
                ConversationAvatar(author: post.author)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(ConversationName.spoken(post.author))님 프로필"))
            .alignmentGuide(.noteNameLine) { $0[.top] + nameCapCenter }

            VStack(alignment: .leading, spacing: 2) {
                header
                    .alignmentGuide(.noteNameLine) { $0[.firstTextBaseline] - nameCapHalf }
                NavigationLink(value: route) {
                    postBody
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("home.post.\(post.id)")
                actions
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 14)
        .onAppear {
            guard likedAtStart == nil else { return }
            if post.likedByMe == true, !liked { likes.set(username: post.author.username, slug: post.slug, on: true) }
            likedAtStart = liked
        }
        .loginPrompt(isPresented: $showLogin, message: "좋아요를 누르려면 로그인하세요")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.row.post.\(post.id)")
    }

    private var postBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                if let excerpt = post.excerpt?.cleanedPreview, !excerpt.isEmpty {
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 4) {
                    Text("블로그 글")
                    if let readMinutes = post.readMinutes {
                        Text(verbatim: "·")
                            .foregroundStyle(Palette.faint)
                            .accessibilityHidden(true)
                        Text("\(readMinutes)분 읽기")
                    }
                    AccessMarks(marks: quoted.access)
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let cover = post.thumbnailUrl.flatMap(URL.init(string:)) {
                PostCoverTile(url: cover)
                    .padding(.top, 8)
            }
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            NavigationLink(value: Route.author(username: post.author.username)) {
                ConversationName(author: post.author)
                    .typeScale(.note)
            }
            .buttonStyle(.plain)
            if let date = post.publishedAt {
                Text(verbatim: "·")
                    .typeScale(.note)
                    .foregroundStyle(Palette.faint)
                    .accessibilityHidden(true)
                Text(date.relativeCompact)
                    .typeScale(.note)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 20) {
            Button {
                likeTaps += 1
                Task { await toggleLike() }
            } label: {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .heart, active: liked, size: Self.actionBox * unit)
                        .modifier(GlyphPop(trigger: reduceMotion ? false : liked))
                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(likeCount)))
                    }
                }
                .typeScale(.lede)
                .foregroundStyle(liked ? Palette.accent : Palette.ink)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
            .accessibilityLabel(Text("좋아요"))
            .accessibilityAddTraits(liked ? [.isSelected] : [])

            NavigationLink(value: route) {
                HStack(spacing: 4) {
                    NoteGlyphView(glyph: .reply, size: Self.actionBox * unit)
                    if let comments = post.commentCount, comments > 0 { Text("\(comments)").monospacedDigit() }
                }
                .typeScale(.lede)
                .foregroundStyle(Palette.ink)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("댓글"))

            Button {
                bookmarkTaps += 1
                CardQuickActions.bookmark(post)
            } label: {
                NoteGlyphView(glyph: .bookmark, active: bookmarked, size: Self.actionBox * unit)
                    .modifier(GlyphPop(trigger: reduceMotion ? false : bookmarked))
                    .foregroundStyle(bookmarked ? Palette.accent : Palette.ink)
                    .expandTapTarget()
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: bookmarkTaps)
            .accessibilityLabel(Text("북마크"))
            .accessibilityAddTraits(bookmarked ? [.isSelected] : [])

            if let url = CardQuickActions.shareURL(post) {
                ShareLink(item: url) {
                    NoteGlyphView(glyph: .share, size: Self.actionBox * unit)
                        .foregroundStyle(Palette.ink)
                        .expandTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("공유"))
            }
            Spacer(minLength: 0)
        }
    }

    private func toggleLike() async {
        guard AuthStore.shared.isSignedIn else {
            showLogin = true
            return
        }
        let target = !liked
        let username = post.author.username, slug = post.slug
        likes.set(username: username, slug: slug, on: target)
        do {
            _ = try await InteractionsAPI.setLike(postId: post.id, on: target)
        } catch {
            likes.set(username: username, slug: slug, on: !target)
            ToastCenter.shared.show(String(localized: "좋아요를 반영하지 못했어요"))
        }
    }
}

private struct PostCoverTile: View {
    let url: URL

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
    }

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                RemoteImage(url: url, slotWidth: 360) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill().allowsHitTesting(false)
                    } else {
                        Palette.hairline
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.hairlineStrong.opacity(0.5), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
