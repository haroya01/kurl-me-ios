//
//  SeriesAnalyticsDetailView.swift
//  kurl
//

import SwiftUI

/// 시리즈 하나의 분석 — 구독자 추이(일별) + 회차별 완주 funnel. 시리즈 목록 행을 누르면 들어온다.
/// funnel = 회차마다 고유 독자 막대가 줄어드는 모습 + "다음 화로 N%" 이어 읽은 비율.
/// 웹 시리즈 분석의 모바일 판(목록만 있던 것을 1뎁스 깊이로 연다).
struct SeriesAnalyticsDetailView: View {
    let seriesId: Int64
    let seriesTitle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var heroSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var phase: LoadState<SeriesAnalyticsDetail> = .idle
    @State private var days = 30

    var body: some View {
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
            case .loaded(let detail):
                content(detail)
            }
        }
        .navigationTitle(seriesTitle)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if case .idle = phase { phase = .loading }
        do {
            let detail = try await AnalyticsAPI.seriesDetail(seriesId: seriesId, days: days)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { phase = .loaded(detail) }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func changeWindow(_ newDays: Int) {
        guard newDays != days else { return }
        days = newDays
        Task { await load() }
    }

    // MARK: 본문

    @ViewBuilder
    private func content(_ detail: SeriesAnalyticsDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                RailHeading("최근 \(detail.windowDays)일")
                Spacer()
                periodChips
            }
            .padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(detail.series.subscriberCount.formatted())
                    .font(.system(size: heroSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text("구독자")
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 14) {
                Label("\(detail.series.postCount)편", systemImage: "doc.text")
                Label("조회 \(detail.series.totalViews)", systemImage: "eye")
                Label("좋아요 \(detail.series.totalLikes)", systemImage: "heart")
            }
            .font(.system(size: 13 * unit))
            .foregroundStyle(Palette.secondary)
            .labelStyle(.titleAndIcon)
        }

        if !detail.subscriberDaily.isEmpty {
            DailyTrendChart(points: detail.subscriberDaily, metricName: String(localized: "구독자"))
        }

        if !detail.members.isEmpty {
            Hairline().padding(.top, 22)
            RailHeading("회차별 완주")
                .padding(.top, 22)
                .padding(.bottom, 4)
            funnel(detail.members)
        }

        Color.clear.frame(height: 32)
    }

    /// 회차 funnel — 고유 독자 막대가 회차마다 줄어드는 모습 + 다음 화 read-through.
    @ViewBuilder
    private func funnel(_ members: [SeriesMemberStat]) -> some View {
        let maxReaders = max(members.map(\.uniqueReaders).max() ?? 1, 1)
        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("EP \(member.episode)")
                        .font(.system(size: 11 * metaUnit, weight: .semibold))
                        .foregroundStyle(Palette.accentMarker)
                    Text(member.title)
                        .font(.system(size: 15 * unit, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.hairline)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.accent.opacity(0.85))
                            .frame(
                                width: max(4, geo.size.width * CGFloat(member.uniqueReaders) / CGFloat(maxReaders)),
                                height: 8)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 8)
                HStack(spacing: 12) {
                    metaCount("person", member.uniqueReaders)
                    metaCount("eye", member.views)
                    metaCount("heart", member.likes)
                    Spacer(minLength: 0)
                    if index < members.count - 1 {
                        let pct = member.uniqueReaders > 0
                            ? Int((Double(member.continuedToNext) / Double(member.uniqueReaders) * 100).rounded())
                            : 0
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10 * metaUnit))
                            Text("다음 화 \(pct)%")
                        }
                        .font(.system(size: 12 * metaUnit, weight: .medium))
                        .foregroundStyle(pct >= 50 ? Palette.accentMarker : Palette.secondary)
                        .accessibilityLabel(Text("다음 화로 \(pct)퍼센트 이어 읽음"))
                    }
                }
            }
            .padding(.vertical, 12)
            if index < members.count - 1 { Hairline() }
        }
    }

    // MARK: 조각

    private var periodChips: some View {
        // 구독자 추이는 7일이 너무 짧아 30·90만. 작가 분석 칩과 같은 유리 문법.
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([30, 90], id: \.self) { option in
                    Button {
                        changeWindow(option)
                    } label: {
                        Text("\(option)일")
                            .font(.system(
                                size: 12 * metaUnit, weight: days == option ? .semibold : .regular))
                            .foregroundStyle(
                                days == option ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassCapsule(prominent: days == option)
                    .accessibilityAddTraits(days == option ? [.isSelected] : [])
                }
            }
        }
    }

    private func metaCount(_ icon: String, _ value: Int64) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10 * metaUnit))
            Text("\(value)").monospacedDigit()
        }
        .font(.system(size: 12 * metaUnit))
        .foregroundStyle(Palette.secondary)
    }
}
