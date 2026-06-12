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
            RailHeading("시리즈")
            Text(detail.series.title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.4)
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
        Hairline()

        // 목차 문법 — 번호·제목·날짜만(소개글은 목차를 늘어뜨린다).
        ForEach(Array(detail.posts.enumerated()), id: \.element.id) { index, post in
            NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.accentMarker)
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(post.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let date = post.publishedAt {
                            Text(date.relativeShort)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            if index < detail.posts.count - 1 { Hairline() }
        }
        Color.clear.frame(height: 40)
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
