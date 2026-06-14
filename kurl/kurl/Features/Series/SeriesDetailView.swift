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
        let posts = detail.posts
        // 읽은(연 적 있는) 회차 — 기기 로컬 기억. @Observable 이라 글을 읽고 돌아오면 갱신된다.
        let readFlags = posts.map { PostReadStore.shared.isRead($0.id) }
        let readCount = readFlags.filter { $0 }.count
        let firstUnread = readFlags.firstIndex(of: false)

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
                    Text("\(posts.count)편")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 읽기 진행 — 시작한 시리즈에만(0이면 '첫 화부터'가 곧 시작 CTA). 그린 마커
            // 진행 막대 + 'N편 중 M편 읽음'. 배너 스테퍼와 같은 언어로 "어디까지 왔나"를 세운다.
            if readCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.hairlineStrong)
                            Capsule().fill(Palette.accentMarker)
                                .frame(
                                    width: geo.size.width
                                        * CGFloat(readCount) / CGFloat(max(posts.count, 1)))
                        }
                    }
                    .frame(height: 4)
                    Text(readCount == posts.count
                         ? "\(posts.count)편 모두 읽음"
                         : "\(posts.count)편 중 \(readCount)편 읽음")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 12) {
                SubscribeButton(seriesId: detail.series.id)
                Spacer(minLength: 0)
                // 시리즈의 본업은 순서대로 읽기 — 읽은 데까지 이어서, 안 시작했으면 첫 화로.
                if let action = seriesAction(posts: posts, readCount: readCount, firstUnread: firstUnread) {
                    NavigationLink(value: Route.post(username: username, slug: action.post.slug)) {
                        HStack(spacing: 5) {
                            Image(systemName: action.icon)
                                .font(.system(size: 12, weight: .semibold))
                            actionLabel(action)
                        }
                        .font(.system(size: 14, weight: .semibold))
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

        // 화별 목차 — 읽은 회차는 체크, 다음 읽을 회차는 표시. 카탈로그(번호 매긴 글 행).
        LazyVStack(spacing: 0) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                    EpisodeRow(
                        number: index + 1, post: post,
                        state: readFlags[index]
                            ? .read
                            : (readCount > 0 && firstUnread == index ? .next : .unread))
                }
                .buttonStyle(RowButtonStyle())
                .modifier(QuietAppear(index: index))
                if index < posts.count - 1 { Hairline() }
            }
        }
        .padding(.bottom, 40)
    }

    /// 본문 시작 문 — 안 읽었으면 첫 화, 읽다 말았으면 첫 미독 회차, 다 읽었으면 처음부터.
    private struct SeriesAction {
        let post: PostListItem
        let icon: String
        let episode: Int?  // 이어 읽기일 때만 회차 번호
    }

    private func seriesAction(posts: [PostListItem], readCount: Int, firstUnread: Int?) -> SeriesAction? {
        guard let first = posts.first else { return nil }
        if readCount == 0 {
            return SeriesAction(post: first, icon: "book", episode: nil)
        }
        if let i = firstUnread {
            return SeriesAction(post: posts[i], icon: "book.fill", episode: i + 1)
        }
        return SeriesAction(post: first, icon: "arrow.counterclockwise", episode: nil)
    }

    @ViewBuilder
    private func actionLabel(_ action: SeriesAction) -> some View {
        if let episode = action.episode {
            Text("이어 읽기 — \(episode)편")
        } else if action.icon == "arrow.counterclockwise" {
            Text("처음부터 다시")
        } else {
            Text("첫 화부터")
        }
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

/// 회차의 읽기 상태 — 읽음(체크)·다음 읽을 차례·아직 안 읽음.
private enum EpisodeState { case read, next, unread }

/// 시리즈 한 화 = 번호 매긴 목차 행. 표지 = 읽음이면 체크, 다음이면 채운 번호, 아직이면 옅은 번호.
/// 카탈로그(순서대로 읽는 책장)라 카드가 아니라 깔끔한 글 행(3원칙 표준).
private struct EpisodeRow: View {
    let number: Int
    let post: PostListItem
    let state: EpisodeState

    @ScaledMetric(relativeTo: .headline) private var titleUnit: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            marker
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(post.title)
                        .typeScale(.title)
                        // 읽은 회차는 한 톤 가라앉혀 — 남은 회차로 눈이 가게.
                        .foregroundStyle(state == .read ? Palette.secondary : Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if state == .next {
                        Text("다음")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.link)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Palette.chipBg, in: Capsule())
                    }
                }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .read:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.accentMarker)
                .frame(width: 32, height: 32)
                .background(Palette.accent.opacity(0.12), in: Circle())
        case .next:
            Text("\(number)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Palette.accent, in: Circle())
        case .unread:
            Text("\(number)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.accentMarker)
                .frame(width: 32, height: 32)
                .background(Palette.accent.opacity(0.10), in: Circle())
        }
    }

    private var a11yLabel: Text {
        let base = "\(number)편 — \(post.title)"
        switch state {
        case .read: return Text("\(base), 읽음")
        case .next: return Text("\(base), 다음 읽을 글")
        case .unread: return Text(base)
        }
    }
}
