//
//  RouteView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// Route 값을 화면으로 분기한다.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case let .post(username, slug):
            PostDetailView(username: username, slug: slug)
        case let .postFocusQuote(username, slug, quote):
            PostDetailView(username: username, slug: slug, focusQuote: quote)
        case let .author(username):
            AuthorBlogView(username: username)
        case let .series(username, slug):
            SeriesDetailView(username: username, slug: slug)
        case let .tag(tag):
            TagFeedView(tag: tag)
        case let .followers(username):
            FollowListsView(username: username, tab: .followers)
        case let .following(username):
            FollowListsView(username: username, tab: .following)
        case let .collection(id):
            CollectionDetailView(collectionId: id)
        }
    }
}
