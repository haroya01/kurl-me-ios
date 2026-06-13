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

        // 화별 목차 — 시리즈는 순서대로 읽는 자리라 카탈로그(번호 매긴 글 행).
        // 카드 대신 ToC 행: 번호 표지 + 제목·소개글·날짜(3원칙 표준).
        LazyVStack(spacing: 0) {
            ForEach(Array(detail.posts.enumerated()), id: \.element.id) { index, post in
                NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                    EpisodeRow(number: index + 1, post: post)
                }
                .buttonStyle(RowButtonStyle())
                .modifier(QuietAppear(index: index))
                if index < detail.posts.count - 1 { Hairline() }
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

/// 시리즈 한 화 = 번호 매긴 목차 행. 번호 표지(그린 톤 원) + 제목·소개글·날짜.
/// 카탈로그(순서대로 읽는 책장)라 카드가 아니라 깔끔한 글 행(3원칙 표준).
private struct EpisodeRow: View {
    let number: Int
    let post: PostListItem

    @ScaledMetric(relativeTo: .headline) private var titleUnit: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 번호 = 화의 표지. 그린 톤 원에 단조 숫자.
            Text("\(number)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.accentMarker)
                .frame(width: 32, height: 32)
                .background(Palette.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let excerpt = post.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 14 * titleUnit))
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
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
