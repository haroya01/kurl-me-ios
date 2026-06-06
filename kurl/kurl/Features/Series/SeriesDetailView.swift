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
        StateView(state: phase, retry: { Task { await load() } }) { detail in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.series.title).font(.title2.bold())
                        Text("\(detail.author.username) · \(detail.series.postCount)편")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(Array(detail.posts.enumerated()), id: \.element.id) { index, post in
                        NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.brand)
                                    .frame(width: 24)
                                PostRow(item: post)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("시리즈")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
