//
//  PostAnalyticsView.swift
//  kurl
//

import Charts
import SwiftUI

/// 글 하나의 분석(facet) — "이 글이 어디서 얼마나 읽혔나"에 들어가는 화면.
/// 개요와 같은 문법: 기간 칩 + 윈도우 히어로 + 일별 추이 + 수명 합계. 글 보기로 탈출구.
struct PostAnalyticsView: View {
    let post: TopPostView

    @State private var phase: LoadState<PostAnalyticsDetail> = .idle
    @State private var days = 30
    /// 독자 분석(고유·유입·국가·기기) — 기간과 무관한 전체. 실패해도 화면은 산다.
    @State private var readStats: PostReadStats?

    var body: some View {
        ReadingColumn(spacing: 0) {
            Text(post.title)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            switch phase {
            case .idle, .loading:
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .failed(let message):
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                        .foregroundStyle(Palette.accent)
                }
                .padding(.top, 40)
            case .loaded(let detail):
                content(detail)
            }
        }
        .navigationTitle("글 분석")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ detail: PostAnalyticsDetail) -> some View {
        HStack(alignment: .center) {
            RailHeading("최근 \(detail.windowDays)일")
            Spacer()
            GlassEffectContainer(spacing: 0) {  // 0 = 닿을 때만 — 칩이 서로 녹아 붙지 않게
                HStack(spacing: 8) {
                    ForEach([7, 30, 90], id: \.self) { option in
                        Button {
                            changeWindow(option)
                        } label: {
                            Text("\(option)일")
                                .font(.system(
                                    size: 12, weight: days == option ? .semibold : .regular))
                                .foregroundStyle(
                                    days == option
                                        ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassCapsule(prominent: days == option)
                    }
                }
            }
        }
        .padding(.top, 22)

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(detail.windowViews.formatted())
                .font(.system(size: 36, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text("조회")
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
        }
        .padding(.top, 6)

        HStack(spacing: 14) {
            Label("팔로우 +\(detail.windowFollows)", systemImage: "person.badge.plus")
            Label("링크 클릭 \(detail.windowLinkClicks)", systemImage: "link")
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.top, 4)

        if !detail.daily.isEmpty {
            Chart(detail.daily) { point in
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
            .frame(height: 150)
            .padding(.top, 14)
        }

        Hairline().padding(.top, 22)
        HStack(spacing: 0) {
            stat("누적 조회", detail.lifetimeViews)
            stat("좋아요", detail.lifetimeLikes)
            stat("팔로우", detail.lifetimeFollows)
            stat("링크 클릭", detail.lifetimeLinkClicks)
        }
        .padding(.vertical, 16)
        Hairline()

        if let readStats { readersSection(readStats) }

        // 분석에서 글로 — 막다른 길 금지.
        if let username = AuthStore.shared.me?.username, !username.isEmpty {
            NavigationLink(value: Route.post(username: username, slug: detail.slug)) {
                HStack(spacing: 6) {
                    Text("글 보기")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.link)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.link)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        Color.clear.frame(height: 32)
    }

    /// 독자 분석 — 웹과 같은 PostReadStats. 고유 방문 헤드라인 + 유입 채널·국가·기기 막대.
    @ViewBuilder
    private func readersSection(_ stats: PostReadStats) -> some View {
        RailHeading("독자")
            .padding(.top, 24)
            .padding(.bottom, 10)
        HStack(spacing: 0) {
            stat("고유 방문", stats.uniqueVisits)
            stat("사람", stats.humanVisits)
            stat("봇", stats.botVisits)
        }
        .padding(.bottom, 4)

        breakdown("유입 채널", stats.sourceChannelVisits.map { (sourceLabel($0.source), $0.count) })
        breakdown("국가", stats.countryVisits.map { ($0.country.uppercased(), $0.count) })
        breakdown("기기", stats.deviceVisits.map { (deviceLabel($0.device), $0.count) })
    }

    /// 막대 목록 — 상위 5개를 비율 막대로(유입 경로와 같은 문법). 비면 그리지 않는다.
    @ViewBuilder
    private func breakdown(_ title: LocalizedStringKey, _ items: [(label: String, count: Int64)]) -> some View {
        if !items.isEmpty {
            let top = Array(items.prefix(5))
            let maxCount = top.map(\.count).max() ?? 1
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.heading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(Array(top.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Text(item.label)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.body)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.accent.opacity(0.25))
                            .frame(
                                width: max(2, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)),
                                height: 8)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    Text("\(item.count)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .frame(height: 26)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(item.label) \(item.count)"))
            }
        }
    }

    private func sourceLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "direct": String(localized: "직접")
        case "social": String(localized: "소셜")
        case "search": String(localized: "검색")
        case "referral": String(localized: "추천")
        case "internal": String(localized: "내부")
        case "newsletter": String(localized: "뉴스레터")
        default: raw
        }
    }

    private func deviceLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "mobile": String(localized: "모바일")
        case "desktop": String(localized: "데스크톱")
        case "tablet": String(localized: "태블릿")
        default: raw
        }
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

    private func changeWindow(_ newDays: Int) {
        guard newDays != days else { return }
        days = newDays
        Task { await load() }
    }

    private func load() async {
        if case .idle = phase { phase = .loading }
        async let statsReq = AnalyticsAPI.readStats(postId: post.postId)
        do {
            phase = .loaded(try await AnalyticsAPI.postAnalytics(postId: post.postId, days: days))
        } catch {
            phase = .failed(error.localizedDescription)
        }
        readStats = try? await statsReq
    }
}
