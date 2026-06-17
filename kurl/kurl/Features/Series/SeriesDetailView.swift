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
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { Task { await load() } }
                            .foregroundStyle(Palette.link)
                    }
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
        // 로드되면 시리즈 제목으로 — 스크롤 시 크롬이 맥락을 다시 세운다. 로딩/실패는 일반 라벨.
        .navigationTitle(navTitle)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var navTitle: String {
        if case .loaded(let detail) = phase { return detail.series.title }
        return "시리즈"
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
                .typeScale(.meta)
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
        // 공개글이 0편이면 죽은 본문 대신 — 작가의 다른 글로 가는 문을 둔다(빈 면도 길을 낸다).
        if posts.isEmpty {
            EmptySeries(author: detail.author)
                .padding(.top, 56)
                .padding(.bottom, 40)
        } else {
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
                    // 카탈로그 행도 피드/검색과 같은 입장(QuietAppear)을 의도적으로 공유 — 목차가
                    // 한 화씩 조용히 차오르는 게 "순서대로 읽는 책장" 결과 맞닿는다(§10.7).
                    .modifier(QuietAppear(index: index))
                    if index < posts.count - 1 { Hairline() }
                }
            }
            .padding(.bottom, 40)
        }
    }

    /// 본문 시작 문 — 안 읽었으면 첫 화, 읽다 말았으면 첫 미독 회차, 다 읽었으면 처음부터.
    /// 의도(kind)를 명시해 둬 라벨·아이콘이 아이콘 문자열 비교로 갈리지 않게 한다.
    private struct SeriesAction {
        enum Kind { case start, resume(Int), restart }
        let post: PostListItem
        let kind: Kind

        var icon: String {
            switch kind {
            case .start: return "book"
            case .resume: return "book.fill"
            case .restart: return "arrow.counterclockwise"
            }
        }
    }

    private func seriesAction(posts: [PostListItem], readCount: Int, firstUnread: Int?) -> SeriesAction? {
        guard let first = posts.first else { return nil }
        if readCount == 0 {
            return SeriesAction(post: first, kind: .start)
        }
        if let i = firstUnread {
            return SeriesAction(post: posts[i], kind: .resume(i + 1))
        }
        return SeriesAction(post: first, kind: .restart)
    }

    @ViewBuilder
    private func actionLabel(_ action: SeriesAction) -> some View {
        Group {
            switch action.kind {
            case .start: Text("첫 화부터")
            case .resume(let episode): Text("이어 읽기 — \(episode)편")
            case .restart: Text("처음부터 다시")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
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
    // 마커 숫자·표지 원 — 큰 글씨에서 번호가 원을 넘치지 않게 프레임도 같이 큰다.
    @ScaledMetric(relativeTo: .footnote) private var markerUnit: CGFloat = 1

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
                        // 회색 캡슐 없이 — "다음"은 그린 글자만으로 충분히 읽힌다.
                        Text("다음")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(Palette.link)
                    }
                }
                if let excerpt = post.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = post.publishedAt {
                    Text(date.relativeShort)
                        .typeScale(.meta)
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
                .font(.system(size: 14 * markerUnit, weight: .bold))
                .foregroundStyle(Palette.accentMarker)
                .frame(width: 32 * markerUnit, height: 32 * markerUnit)
                .background(Palette.accent.opacity(0.12), in: Circle())
        case .next:
            Text("\(number)")
                .font(.system(size: 15 * markerUnit, weight: .bold).monospacedDigit())
                // 흰 라벨 채움 = accent-700(WCAG 4.5:1) — 600은 흰 글자 대비 미달(§10.3).
                .foregroundStyle(.white)
                .frame(width: 32 * markerUnit, height: 32 * markerUnit)
                .background(Palette.accentFill, in: Circle())
        case .unread:
            Text("\(number)")
                .font(.system(size: 15 * markerUnit, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.accentMarker)
                .frame(width: 32 * markerUnit, height: 32 * markerUnit)
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

/// 공개 회차가 0편인 시리즈 — 빈 본문 대신 작가 면으로 가는 문(FeedPlaceholder 와 같은 언어).
/// 닫힌 막다른 길이 아니라 작가의 다른 글로 이어주는 게 핵심이라 CTA = NavigationLink.
private struct EmptySeries: View {
    let author: Author

    var body: some View {
        VStack(spacing: 0) {
            // 빈 면의 브랜드 사인 — 형광 아닌 옅은 잉크(FeedPlaceholder 와 동일).
            KurlMark(drawn: [true, true, true], tint: Palette.hairlineStrong)
                .frame(width: 46, height: 28)
                .accessibilityHidden(true)
                .padding(.bottom, 24)

            Text("준비 중")
                .typeScale(.eyebrow)
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 10)

            Text("아직 공개된 회차가 없어요")
                .typeScale(.featured)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 9)

            Text("첫 화가 올라오면 여기에서 순서대로 읽을 수 있어요.")
                .typeScale(.lede)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 272)
                .padding(.bottom, 22)

            NavigationLink(value: Route.author(username: author.username)) {
                Text("\(author.username)의 다른 글")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .glassCapsule(prominent: true)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
    }
}
