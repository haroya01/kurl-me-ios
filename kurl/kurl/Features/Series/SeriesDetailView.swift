//
//  SeriesDetailView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct SeriesDetailView: View {
    let username: String
    let slug: String

    @State private var phase: LoadState<PublicSeriesDetail> = .idle

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch phase {
                case .idle, .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                           description: Text(message))
                        .padding(.top, 80)
                case .loaded(let detail):
                    content(detail)
                }
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.pageBg)
        .navigationTitle("시리즈")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ detail: PublicSeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                KurlMark(drawn: [true, true, true])
                    .frame(width: 18, height: 11)
                RailHeading("시리즈")
            }
            Text(detail.series.title)
                .typeScale(.masthead)
                .foregroundStyle(Palette.ink)
            NavigationLink(value: Route.author(username: detail.author.username)) {
                HStack(spacing: 6) {
                    Text(detail.author.username)
                        .fontWeight(.medium)
                    Text("·").foregroundStyle(Palette.faint)
                    Text("\(detail.series.postCount)편")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                SubscribeButton(seriesId: detail.series.id)
                Spacer(minLength: 0)
                // 시리즈의 본업은 순서대로 읽기 — 1화 직행 문을 단다.
                if let first = detail.posts.first {
                    NavigationLink(value: Route.post(username: username, slug: first.slug)) {
                        HStack(spacing: 5) {
                            Image(systemName: "book")
                                .font(.system(size: 12, weight: .semibold))
                            Text("첫 화부터")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 16)

        // 화별 카드 — 시리즈가 책장의 한 칸씩 읽히게. 번호는 카드 안 에피소드 표지로.
        LazyVStack(spacing: 14) {
            ForEach(Array(detail.posts.enumerated()), id: \.element.id) { index, post in
                NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                    EpisodeCard(number: index + 1, post: post)
                }
                .buttonStyle(CardButtonStyle())
                .modifier(QuietAppear(index: index))
                .modifier(CardScrollFade())
            }
        }
        .padding(.bottom, 40)
    }

    private func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            phase = .loaded(try await BlogAPI.seriesDetail(username: username, slug: slug))
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}

/// 시리즈 한 화 = 카드. 왼쪽 표지(없으면 번호 타일) + 화 번호 eyebrow + 제목·소개글·날짜.
/// browse 카드(BlogCard)와 같은 표면 언어 — 라이트는 그림자, 다크는 보더.
private struct EpisodeCard: View {
    let number: Int
    let post: PostListItem

    @ScaledMetric(relativeTo: .headline) private var titleUnit: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    private let radius = Metrics.radiusCard

    var body: some View {
        HStack(spacing: 14) {
            thumb
            VStack(alignment: .leading, spacing: 4) {
                Text("\(number)화")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .tracking(0.3)
                    .foregroundStyle(Palette.accentMarker)
                Text(post.title)
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let excerpt = post.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 13 * titleUnit))
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = post.publishedAt {
                    Text(date.relativeShort)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.cardBg, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
        }
        .cardShadow()
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder
    private var thumb: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
        if let urlString = post.ogImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Palette.hairline)
            }
            .saturation(0.85)
            .frame(width: 76, height: 76)
            .overlay(Palette.coverVeil)
            .clipShape(shape)
        } else {
            // 표지 없는 화 — 번호를 표지 삼은 그린 톤 타일.
            shape
                .fill(Palette.accent.opacity(0.10))
                .frame(width: 76, height: 76)
                .overlay {
                    KurlMark(drawn: [true, true, true])
                        .frame(width: 26, height: 16)
                        .opacity(0.55)
                }
        }
    }
}
