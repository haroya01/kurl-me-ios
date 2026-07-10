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
    /// 진행률 메타(mono digit) — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var progressSize: CGFloat = 12

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
        // 로드되면 마스트헤드 H1 이 제목의 유일한 주인 — 상단 바 제목을 비워 같은 제목이
        // 두 번 겹치지 않게 한다(웹 시리즈 뷰처럼 마스트헤드가 스크롤로 조용히 물러난다).
        // 로딩·실패엔 마스트헤드가 없으니 일반 라벨로 맥락을 세운다.
        .navigationTitle(navTitle)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var navTitle: String {
        if case .loaded = phase { return "" }
        return "시리즈"
    }

    @ViewBuilder
    private func content(_ detail: PublicSeriesDetail) -> some View {
        let posts = detail.posts
        // 읽은(연 적 있는) 회차 — 기기 로컬 기억. @Observable 이라 글을 읽고 돌아오면 갱신된다.
        let readFlags = posts.map { PostReadStore.shared.isRead($0.id) }
        let readCount = readFlags.filter { $0 }.count
        let firstUnread = readFlags.firstIndex(of: false)

        masthead(detail: detail, posts: posts, readCount: readCount, firstUnread: firstUnread)

        // 화별 목차 — 읽은 회차는 체크, 다음 읽을 회차는 번호가 밝아진다. 카탈로그(번호 매긴 글 행).
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

    /// 에디토리얼 마스트헤드 — 시리즈 정체(제목·작가·규모·주제)를 세우고, 구분선 아래에
    /// "이어서 읽기" 한 동작으로 목차를 연다. 종이 세계라 유리는 컨트롤(구독·읽기 캡슐)에만.
    @ViewBuilder
    private func masthead(
        detail: PublicSeriesDetail, posts: [PostListItem], readCount: Int, firstUnread: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                KurlMark(drawn: [true, true, true])
                    .frame(width: 18, height: 11)
                    .accessibilityHidden(true)
                Text("시리즈")
                    .typeScale(.eyebrow)
                    .foregroundStyle(Palette.heading)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(detail.series.title)
                .typeScale(.masthead)
                .foregroundStyle(Palette.ink)
                .padding(.top, 10)

            // 작가 = 여백의 서명. 아바타 + 이름 한 줄이 시리즈의 주인을 세운다(웹 좌측 레일 번역).
            NavigationLink(value: Route.author(username: detail.author.username)) {
                HStack(spacing: 8) {
                    AvatarView(author: detail.author, size: 22)
                    Text(detail.author.username)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.body)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            // 규모·주제 — 번호를 전면에(몇 편짜리 여정인지)와 태그 한 가닥. 회색 칩 없이 글자만(§10).
            scopeLine(posts: posts, tags: detail.series.tags)
                .padding(.top, 7)

            // 구독 = 관계(새 글 알림). 읽기(주행동)와 색을 다투지 않게 여기선 가라앉힌 보조 유리로.
            SubscribeButton(seriesId: detail.series.id, emphasis: .secondary)
                .padding(.top, 16)

            Hairline()
                .padding(.top, 18)

            // 이어서 읽기 블록 — 진행 막대 + 주행동 하나로 "어디까지 왔고, 어디서 잇는지"를 묶는다.
            continueBlock(posts: posts, readCount: readCount, firstUnread: firstUnread)
                .padding(.top, 18)
        }
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    /// 규모 + 주제 한 줄. 총 편수는 시리즈의 뼈대(몇 편짜리 여정인지), 태그는 눌러 그 주제 피드로.
    @ViewBuilder
    private func scopeLine(posts: [PostListItem], tags: [String]) -> some View {
        HStack(spacing: 8) {
            Text("\(posts.count)편")
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
            // 최대 세 개까지 — 좁은 폭에서 마스트헤드가 태그로 넘치지 않게.
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text(verbatim: "·")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.faint)
                NavigationLink(value: Route.tag(tag)) {
                    Text(verbatim: "#\(tag)")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
    }

    /// 진행 막대 + 주행동. 시작 전이면 막대 없이 '첫 화부터'만, 읽는 중이면 진행 위에 '이어 읽기'.
    @ViewBuilder
    private func continueBlock(posts: [PostListItem], readCount: Int, firstUnread: Int?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if readCount > 0 {
                VStack(alignment: .leading, spacing: 7) {
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
                        .font(.system(size: progressSize).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            // 시리즈의 본업은 순서대로 읽기 — 읽은 데까지 이어서, 안 시작했으면 첫 화로.
            // 주행동이라 그린 유리 캡슐(흰 라벨). 화면에 그린 primary 는 이 하나뿐이게 한다.
            if let action = seriesAction(posts: posts, readCount: readCount, firstUnread: firstUnread) {
                NavigationLink(value: Route.post(username: username, slug: action.post.slug)) {
                    HStack(spacing: 7) {
                        Image(systemName: action.icon)
                            .font(.system(size: 13, weight: .semibold))
                        actionLabel(action)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassCapsule(prominent: true)
            }
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

/// 시리즈 한 화 = 번호 매긴 목차 행. 왼쪽 뼈대(spine) = 웹로그 관용의 모노 두 자리 번호(01·02…),
/// 읽음이면 체크로 접히고 다음 읽을 회차만 그린으로 밝아진다 — 원(테두리) 없이 번호가 앞에 선다.
/// 카탈로그(순서대로 읽는 책장)라 카드가 아니라 깔끔한 글 행(3원칙 표준).
private struct EpisodeRow: View {
    let number: Int
    let post: PostListItem
    let state: EpisodeState
    // 큰 글씨에서도 뼈대 번호가 제목과 함께 커지게(고정 pt 우회).
    @ScaledMetric(relativeTo: .footnote) private var spineUnit: CGFloat = 1
    /// "다음" 라벨 — 사다리에 딱 맞는 롤이 없어(고유 자간) 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var nextSize: CGFloat = 11

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            spine
                .frame(width: 24 * spineUnit, alignment: .leading)
                .padding(.top, 3)
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
                            .font(.system(size: nextSize, weight: .bold))
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
    private var spine: some View {
        switch state {
        case .read:
            // 다 읽은 회차 = 접힌 체크. 그린 과용을 걷어내려 마커색이 아닌 옅은 잉크로 물러앉힌다.
            Image(systemName: "checkmark")
                .font(.system(size: 13 * spineUnit, weight: .bold))
                .foregroundStyle(Palette.faint)
        case .next:
            // 지금 이어 읽을 회차 = 그린으로 밝아지는 번호(화면에서 이 번호 하나만 형광).
            Text(String(format: "%02d", number))
                .font(.system(size: 15 * spineUnit, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.link)
        case .unread:
            Text(String(format: "%02d", number))
                .font(.system(size: 15 * spineUnit, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.secondary)
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
    /// CTA 라벨 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .callout) private var ctaSize: CGFloat = 15

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
                    .font(.system(size: ctaSize, weight: .semibold))
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
