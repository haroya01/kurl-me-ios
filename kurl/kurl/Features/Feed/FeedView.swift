//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct FeedView: View {
    @State private var model = FeedViewModel()

    var body: some View {
        NavigationStack {
            StateView(state: model.phase, retry: { Task { await model.reload() } }) { _ in
                feedList
            }
            .navigationTitle("kurl")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $model.sort) {
                        ForEach(FeedSort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .task { await model.loadInitial() }
    }

    private var feedList: some View {
        List {
            ForEach(model.items) { item in
                NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                    FeedCard(item: item)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .task { await model.loadMoreIfNeeded(current: item) }
            }
            if model.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await model.reload() }
    }
}
