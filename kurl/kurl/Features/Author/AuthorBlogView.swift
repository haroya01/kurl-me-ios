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
    @State private var showNavTitle = false

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
        // 헤더를 지나면 작가 이름이 내비바로 스민다 — 상단 중복 제거(태그·글 상세와 같은 결).
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, passed in
            withAnimation(.easeInOut(duration: 0.18)) { showNavTitle = passed }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(username)
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(showNavTitle ? 1 : 0)
            }
        }
        .toolbarBackground(showNavTitle ? .automatic : .hidden, for: .navigationBar)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ view: PublicPostListView) -> some View {
        // 정체 헤더 = 작가 랜딩 마스트헤드(태그·시리즈와 같은 family — eyebrow + 히어로).
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("작가")
                .padding(.top, 8)
                .padding(.bottom, 14)
            HStack(alignment: .center, spacing: 14) {
                AvatarView(author: view.author, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(view.author.username)
                        .typeScale(.name)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
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
                                    KurlMark(drawn: [true, true, true])
                                        .frame(width: 18, height: 11)
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
                                    in: RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(CardButtonStyle())
                            .modifier(CardScrollFade(axis: .horizontal))
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }

        RailHeading("글").padding(.bottom, 4)
        // 작가 글 목록 = 카탈로그(작가의 책장) — 카드가 아니라 깔끔한 글 행(PostRow).
        // 발견·검색·태그만 카드, 읽기·카탈로그 면은 행(3원칙 표준).
        LazyVStack(spacing: 0) {
            ForEach(Array(view.posts.enumerated()), id: \.element.id) { index, post in
                NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                    PostRow(item: post)
                }
                .buttonStyle(RowButtonStyle())
                .modifier(QuietAppear(index: index))
                if index < view.posts.count - 1 { Hairline() }
            }
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
