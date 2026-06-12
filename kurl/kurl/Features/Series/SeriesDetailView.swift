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
                .font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.ink)
            Text("\(detail.author.username) · \(detail.series.postCount)편")
                .font(.system(size: 14)).foregroundStyle(Palette.secondary)
            SubscribeButton(seriesId: detail.series.id)
                .padding(.top, 6)
        }
        .padding(.vertical, 16)
        Hairline()

        ForEach(Array(detail.posts.enumerated()), id: \.element.id) { index, post in
            NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                HStack(alignment: .top, spacing: 14) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.accentMarker)
                        .frame(width: 22, alignment: .leading)
                        .padding(.top, 18)
                    PostRow(item: post)
                }
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
