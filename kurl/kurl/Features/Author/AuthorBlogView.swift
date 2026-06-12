//
//  AuthorBlogView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct AuthorBlogView: View {
    let username: String

    @State private var phase: LoadState<PublicPostListView> = .idle
    @State private var series: [SeriesListItem] = []
    @State private var showCard = false

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
                case .loaded(let view):
                    content(view)
                }
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.pageBg)
        .navigationTitle(username)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ view: PublicPostListView) -> some View {
        // 정체 헤더 — 이름·소개·산출물 한 줄(글·시리즈 수)이 한눈에.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                AvatarView(author: view.author, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(view.author.username)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 6) {
                        Text("글 \(view.posts.count)")
                        if !series.isEmpty {
                            Text("·").foregroundStyle(Palette.faint)
                            Text("시리즈 \(series.count)")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            if let bio = view.author.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(4)
                    .padding(.top, 12)
            }
            HStack(spacing: 10) {
                FollowButton(username: view.author.username)
                Spacer(minLength: 0)
                // 명함(u/ — 링크 모음·소셜)으로 가는 문 — 블로그와 같은 정체의 다른 얼굴.
                Button {
                    showCard = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("명함")
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
            .padding(.top, 14)
        }
        .padding(.vertical, 18)
        .sheet(isPresented: $showCard) {
            if let url = URL(
                string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/u/\(username)") {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }

        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                RailHeading("시리즈")
                // 세로 행 대신 가로 레일 — 시리즈가 프로필의 책장처럼 읽히게.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(series) { item in
                            NavigationLink(
                                value: Route.series(username: username, slug: item.slug)
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: "square.stack.3d.up")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Palette.accentMarker)
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Text("\(item.postCount)편")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.secondary)
                                }
                                .padding(13)
                                .frame(width: 148, height: 108, alignment: .topLeading)
                                .background(
                                    Palette.chipBg,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }

        RailHeading("글").padding(.bottom, 6)
        Hairline()
        ForEach(Array(view.posts.enumerated()), id: \.element.id) { index, post in
            NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                PostRow(item: post)
            }
            .buttonStyle(RowButtonStyle())
            if index < view.posts.count - 1 { Hairline() }
        }
        Color.clear.frame(height: 40)
    }

    private func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            let view = try await BlogAPI.authorPosts(username: username)
            phase = .loaded(view)
            series = (try? await BlogAPI.authorSeries(username: username))?.series ?? []
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
