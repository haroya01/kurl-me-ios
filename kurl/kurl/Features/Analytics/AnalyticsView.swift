//
//  AnalyticsView.swift
//  kurl
//

import SwiftUI

/// 작가 분석 — 웹 /write 분석의 모바일 판. 30일 조회 추이가 히어로, 그 아래
/// 윈도우 보조지표(팔로우·링크 클릭) → 누적 스탯 → 글별 성과(정렬·더보기) →
/// 시리즈 → 유입 경로. 성공적으로 읽을 때마다 홈 위젯용 스냅샷을 남긴다.
struct AnalyticsView: View {
    /// 스튜디오 분면으로 품길 때 true — 내비 타이틀을 건드리지 않는다(스튜디오 소유).
    var embedded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var heroSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var phase: LoadState<AuthorAnalyticsOverview> = .idle
    @State private var performance: PostPerformanceResult?
    @State private var performanceSort = "views"
    @State private var loadingMorePosts = false
    @State private var series: [SeriesAnalyticsRow] = []
    @State private var days = 30
    @State private var selectedPost: TopPostView?
    @State private var selectedSeries: SeriesAnalyticsRow?

    var body: some View {
        if embedded {
            core
        } else {
            core
                .navigationTitle("분석")
                .toolbarRole(.editor)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var core: some View {
        ReadingColumn(spacing: 0) {
            switch phase {
            case .idle, .loading:
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 280)
            case .failed(let message):
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                        .foregroundStyle(Palette.accent)
                }
                .padding(.top, 60)
            case .loaded(let overview):
                content(overview)
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostAnalyticsView(post: post)
        }
        .navigationDestination(item: $selectedSeries) { row in
            SeriesAnalyticsDetailView(seriesId: row.seriesId, seriesTitle: row.title)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if case .idle = phase { phase = .loading }
        do {
            async let overviewReq = AnalyticsAPI.overview(days: days)
            async let performanceReq = AnalyticsAPI.postPerformance(sort: performanceSort)
            async let seriesReq = AnalyticsAPI.seriesAnalytics()
            let overview = try await overviewReq
            let nextPerformance = try? await performanceReq
            let nextSeries = (try? await seriesReq) ?? []
            // 트랜잭션 밖 교체는 numericText·차트 보간을 전부 죽인다 — 한 호흡에 굴린다.
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                performance = nextPerformance
                series = nextSeries
                phase = .loaded(overview)
            }
            AnalyticsSnapshot.save(from: overview)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func changeWindow(_ newDays: Int) {
        guard newDays != days else { return }
        days = newDays
        Task { await load() }
    }

    private func resort(_ sort: String) {
        guard sort != performanceSort else { return }
        performanceSort = sort
        Task {
            // 실패 시 기존 목록 유지 + 칩이 또 바뀌었으면 스테일 응답 폐기.
            if let next = try? await AnalyticsAPI.postPerformance(sort: sort),
               sort == performanceSort {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                    performance = next
                }
            }
        }
    }

    private func loadMorePosts() {
        guard let current = performance, current.hasNext, !loadingMorePosts else { return }
        loadingMorePosts = true
        let sortAtStart = performanceSort
        Task {
            defer { loadingMorePosts = false }
            if let next = try? await AnalyticsAPI.postPerformance(
                sort: sortAtStart, page: current.page + 1),
               sortAtStart == performanceSort
            {
                performance = PostPerformanceResult(
                    items: current.items + next.items, page: next.page, hasNext: next.hasNext)
            }
        }
    }

    // MARK: 본문

    @ViewBuilder
    private func content(_ overview: AuthorAnalyticsOverview) -> some View {
        hero(overview)
        lifetime(overview)
        postPerformanceSection
        seriesSection
        referrers(overview)
        Color.clear.frame(height: 32)
    }

    @ViewBuilder
    private func hero(_ overview: AuthorAnalyticsOverview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                RailHeading("최근 \(overview.windowDays)일")
                Spacer()
                // 기간은 서버가 받는 파라미터 — 30일 고정 리포트를 끝낸다.
                GlassEffectContainer(spacing: 0) {  // 0 = 닿을 때만 — 칩이 서로 녹아 붙지 않게
                    HStack(spacing: 8) {
                        ForEach([7, 30, 90], id: \.self) { option in
                            Button {
                                changeWindow(option)
                            } label: {
                                Text("\(option)일")
                                    .font(.system(
                                        size: 12 * metaUnit,
                                        weight: days == option ? .semibold : .regular))
                                    .foregroundStyle(
                                        days == option
                                            ? AnyShapeStyle(Color(uiColor: .systemBackground))
                                            : AnyShapeStyle(.secondary))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .selectorPill(selected: days == option)
                            .accessibilityAddTraits(days == option ? [.isSelected] : [])
                        }
                    }
                }
            }
            .padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(overview.windowViews.formatted())
                    .font(.system(size: heroSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("조회")
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(Palette.secondary)
            }
            // 윈도우 보조지표 — 아이콘 군집 대신 담백한 한 줄(§10 절제).
            metaLine(["팔로우 +\(overview.windowFollows)", "링크 클릭 \(overview.windowLinkClicks)"])
                .padding(.top, 2)
        }

        if !overview.daily.isEmpty {
            DailyTrendChart(points: overview.daily)
        }
    }

    @ViewBuilder
    private func lifetime(_ overview: AuthorAnalyticsOverview) -> some View {
        Hairline().padding(.top, 22)
        HStack(spacing: 0) {
            stat("발행한 글", overview.publishedPosts)
            stat("누적 조회", overview.lifetimeViews)
            stat("좋아요", overview.lifetimeLikes)
            stat("팔로워", overview.lifetimeFollows)
            stat("링크 클릭", overview.lifetimeLinkClicks)
        }
        .padding(.vertical, 16)
        Hairline()
    }

    @ViewBuilder
    private var postPerformanceSection: some View {
        if let performance, !performance.items.isEmpty {
            HStack(alignment: .center) {
                RailHeading("글별 성과")
                Spacer()
                // 정렬 = 유리 칩 클러스터 — 가까이 붙어 서로 녹아 보이는 컨트롤 군.
                GlassEffectContainer(spacing: 0) {  // 0 = 닿을 때만 — 칩이 서로 녹아 붙지 않게
                    HStack(spacing: 8) {
                        sortChip("조회", key: "views")
                        sortChip("좋아요", key: "likes")
                        sortChip("최신", key: "recent")
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 4)

            ForEach(Array(performance.items.enumerated()), id: \.element.id) { index, row in
                // 행 탭 = 그 글의 facet — "이 글이 어디서 얼마나 읽혔나"로 들어가는 문.
                Button {
                    selectedPost = row
                } label: {
                    // 정규 "글 행" 언어 — 순위 숫자 column 을 빼고(순서·지표값이 곧 순위)
                    // 제목 18 + 메타 카운트로 스튜디오·작가 목록과 한 결.
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title)
                                .typeScale(.title)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            metaLine(
                                ["조회 \(row.viewCount.formatted())",
                                 "좋아요 \(row.likeCount.formatted())"]
                                + (row.followsGained > 0
                                    ? ["팔로우 \(row.followsGained.formatted())"] : []))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11 * metaUnit, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
                if index < performance.items.count - 1 {
                    Hairline()
                }
            }

            if performance.hasNext {
                Button {
                    loadMorePosts()
                } label: {
                    if loadingMorePosts {
                        ProgressView().tint(Palette.accent)
                    } else {
                        Text("더 보기")
                            .font(.system(size: 13 * unit, weight: .medium))
                            .foregroundStyle(Palette.link)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var seriesSection: some View {
        if !series.isEmpty {
            RailHeading("시리즈")
                .padding(.top, 24)
                .padding(.bottom, 4)
            ForEach(Array(series.enumerated()), id: \.element.id) { index, row in
                // 행 탭 = 시리즈 facet — 구독자 추이 + 회차별 완주 funnel 로 들어가는 문.
                Button {
                    selectedSeries = row
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .typeScale(.title)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            metaLine([
                                "\(row.postCount)편", "구독 \(row.subscriberCount.formatted())",
                                "조회 \(row.totalViews.formatted())",
                                "좋아요 \(row.totalLikes.formatted())",
                            ])
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11 * metaUnit, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
                if index < series.count - 1 {
                    Hairline()
                }
            }
        }
    }

    @ViewBuilder
    private func referrers(_ overview: AuthorAnalyticsOverview) -> some View {
        if !overview.referrers.isEmpty {
            RailHeading("유입 경로")
                .padding(.top, 24)
                .padding(.bottom, 6)
            let maxViews = overview.referrers.map(\.views).max() ?? 1
            ForEach(overview.referrers) { ref in
                HStack(spacing: 10) {
                    Text(ref.host)
                        .font(.system(size: 14 * unit))
                        .foregroundStyle(Palette.body)
                        .lineLimit(1)
                        .frame(width: 120 * unit, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.accent.opacity(0.25))
                            .frame(
                                width: max(2, geo.size.width * CGFloat(ref.views) / CGFloat(maxViews)),
                                height: 8
                            )
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    Text("\(ref.views)")
                        .font(.system(size: 13 * unit).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .frame(height: 28 * unit)
            }
        }
    }

    // MARK: 조각

    private func sortChip(_ label: LocalizedStringKey, key: String) -> some View {
        let active = performanceSort == key
        return Button {
            resort(key)
        } label: {
            Text(label)
                .font(.system(size: 12 * metaUnit, weight: active ? .semibold : .regular))
                .foregroundStyle(active
                    ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .selectorPill(selected: active)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    /// 절제 — 작은 아이콘 군집 대신 muted 텍스트 한 줄(라벨·값을 가운뎃점으로). 텍스트라
    /// VoiceOver 도 그대로 읽힌다. 메타에서 아이콘을 걷어내는 게 "조용함"의 큰 부분(§10).
    private func metaLine(_ parts: [String]) -> some View {
        Text(parts.joined(separator: "  ·  "))
            .font(.system(size: 13 * metaUnit))
            .foregroundStyle(Palette.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private func stat(_ label: LocalizedStringKey, _ value: Int64) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted())
                .font(.system(size: 17 * unit, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11 * metaUnit))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
