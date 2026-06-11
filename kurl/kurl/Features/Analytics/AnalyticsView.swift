//
//  AnalyticsView.swift
//  kurl
//

import Charts
import SwiftUI

/// 작가 분석 — 웹 /write 분석 개요의 모바일 판. 30일 조회 추이가 히어로,
/// 그 아래 누적 스탯과 유입 경로. 성공적으로 읽을 때마다 홈 위젯용 스냅샷을 남긴다.
struct AnalyticsView: View {
    @State private var phase: LoadState<AuthorAnalyticsOverview> = .idle

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
            let overview = try await AnalyticsAPI.overview()
            phase = .loaded(overview)
            AnalyticsSnapshot.save(from: overview)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func content(_ overview: AuthorAnalyticsOverview) -> some View {
        // 히어로 — 윈도우 조회수 + 일별 추이
        VStack(alignment: .leading, spacing: 6) {
            RailHeading("최근 \(overview.windowDays)일")
                .padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(overview.windowViews)")
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("조회")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.secondary)
            }
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
                AxisMarks { value in
                    AxisValueLabel()
                        .font(.system(size: 9))
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

        // 누적 스탯
        Hairline().padding(.top, 22)
        HStack(spacing: 0) {
            stat("발행한 글", overview.publishedPosts)
            stat("누적 조회", overview.lifetimeViews)
            stat("좋아요", overview.lifetimeLikes)
            stat("팔로워", overview.lifetimeFollows)
        }
        .padding(.vertical, 16)
        Hairline()

        // 유입 경로
        if !overview.referrers.isEmpty {
            RailHeading("유입 경로")
                .padding(.top, 22)
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

        Color.clear.frame(height: 32)
    }

    private func stat(_ label: String, _ value: Int64) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
