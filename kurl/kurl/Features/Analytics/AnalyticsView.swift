//
//  AnalyticsView.swift
//  kurl
//

import Charts
import SwiftUI

/// 작가 분석 — 웹 /write 분석의 모바일 판. 30일 조회 추이가 히어로, 그 아래
/// 윈도우 보조지표(팔로우·링크 클릭) → 누적 스탯 → 글별 성과(정렬·더보기) →
/// 시리즈 → 유입 경로. 성공적으로 읽을 때마다 홈 위젯용 스냅샷을 남긴다.
struct AnalyticsView: View {
    @State private var phase: LoadState<AuthorAnalyticsOverview> = .idle
    @State private var performance: PostPerformanceResult?
    @State private var performanceSort = "views"
    @State private var loadingMorePosts = false
    @State private var series: [SeriesAnalyticsRow] = []

    var body: some View {
        ReadingColumn(spacing: 0) {
            switch phase {
            case .idle, .loading:
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 280)
            case .failed(let message):
                ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                       description: Text(message))
                    .padding(.top, 60)
            case .loaded(let overview):
                content(overview)
            }
        }
        .navigationTitle("분석")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if case .idle = phase { phase = .loading }
        do {
            async let overviewReq = AnalyticsAPI.overview()
            async let performanceReq = AnalyticsAPI.postPerformance(sort: performanceSort)
            async let seriesReq = AnalyticsAPI.seriesAnalytics()
            let overview = try await overviewReq
            performance = try? await performanceReq
            series = (try? await seriesReq) ?? []
            phase = .loaded(overview)
            AnalyticsSnapshot.save(from: overview)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func resort(_ sort: String) {
        guard sort != performanceSort else { return }
        performanceSort = sort
        Task {
            // 실패 시 기존 목록 유지 + 칩이 또 바뀌었으면 스테일 응답 폐기.
            if let next = try? await AnalyticsAPI.postPerformance(sort: sort),
               sort == performanceSort {
                performance = next
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
            RailHeading("최근 \(overview.windowDays)일")
                .padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(overview.windowViews.formatted())
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("조회")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.secondary)
            }
            // 윈도우 보조지표 — 팔로우 전환과 본문 kurl 링크 클릭.
            HStack(spacing: 14) {
                Label("팔로우 +\(overview.windowFollows)", systemImage: "person.badge.plus")
                Label("링크 클릭 \(overview.windowLinkClicks)", systemImage: "link")
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.secondary)
            .labelStyle(.titleAndIcon)
        }

        if !overview.daily.isEmpty {
            Chart(overview.daily) { point in
                BarMark(
                    x: .value("일", point.dayLabel),
                    y: .value("조회", point.views)
                )
                .foregroundStyle(Palette.accent.opacity(0.85))
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.faint)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.faint)
                }
            }
            .frame(height: 140)
            .padding(.top, 14)
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
            HStack(alignment: .firstTextBaseline) {
                RailHeading("글별 성과")
                Spacer()
                HStack(spacing: 6) {
                    sortChip("조회", key: "views")
                    sortChip("좋아요", key: "likes")
                    sortChip("최신", key: "recent")
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 4)

            ForEach(Array(performance.items.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(index < 3 ? Palette.link : Palette.secondary)
                        .frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            metaCount("eye", row.viewCount)
                            metaCount("heart", row.likeCount)
                            if row.followsGained > 0 {
                                metaCount("person.badge.plus", row.followsGained)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
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
                            .font(.system(size: 13, weight: .medium))
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Text("\(row.postCount)편")
                        metaCount("person.2", row.subscriberCount)
                        metaCount("eye", row.totalViews)
                        metaCount("heart", row.totalLikes)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                }
                .padding(.vertical, 9)
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
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.body)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
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
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .frame(height: 28)
            }
        }
    }

    // MARK: 조각

    private func sortChip(_ label: LocalizedStringKey, key: String) -> some View {
        Button {
            resort(key)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: performanceSort == key ? .semibold : .regular))
                .foregroundStyle(performanceSort == key ? Palette.link : Palette.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    if performanceSort == key {
                        Capsule().fill(Palette.chipBg)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func metaCount(_ icon: String, _ value: Int64) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text("\(value)").monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.secondary)
    }

    private func stat(_ label: LocalizedStringKey, _ value: Int64) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted())
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
