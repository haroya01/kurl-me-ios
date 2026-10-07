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
        case let .postSpot(username, slug, spot):
            PostDetailView(username: username, slug: slug, focusSpot: spot)
        case let .author(username):
            AuthorBlogView(username: username)
        case let .authorNotes(username):
            AuthorBlogView(username: username, initialTab: .notes)
        case let .businessCard(username):
            BusinessCardView(username: username)
        case let .series(username, slug):
            SeriesDetailView(username: username, slug: slug)
        case let .tag(tag):
            TagFeedView(tag: tag)
        case let .noteTag(tag):
            TagFeedView(tag: tag, initialTab: .notes)
        case let .followers(username):
            FollowListsView(username: username, tab: .followers)
        case let .following(username):
            FollowListsView(username: username, tab: .following)
        case let .collection(id):
            CollectionDetailView(collectionId: id)
        case .notifications:
            NotificationsView()
        case let .note(id):
            NoteDetailView(noteId: id)
        case let .noteQuotes(id):
            NoteQuotesView(noteId: id)
        case let .remoteAccount(id):
            RemoteAccountView(accountId: id)
        }
    }
}
