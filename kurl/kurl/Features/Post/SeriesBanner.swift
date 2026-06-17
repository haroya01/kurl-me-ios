//
//  SeriesBanner.swift
//  kurl
//

import SwiftUI

/// 글 상단의 시리즈 배너 — 웹 SeriesNav 의 네이티브 번역(그린 좌측 룰 + 진행 스테퍼 +
/// 접이식 회차 목록). 읽기 전에 "이 글이 여정의 몇 번째인지"를 세우는 자리라 본문(종이)
/// 문법을 쓴다 — 유리 금지. 회차 목록은 첫 펼침에만 가져온다(안 펼치면 네트워크 0).
struct SeriesBanner: View {
    let nav: PostSeriesNav
    let username: String
    let currentSlug: String

    @State private var expanded = false
    @State private var episodes: [PostListItem]?
    @State private var loadFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 핵심 읽기면이라 고정 pt 금지 — typeScale 못 쓰는 자리(monospacedDigit·소형 라벨)는 배수로 키운다.
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: Route.series(username: username, slug: nav.slug)) {
                HStack(spacing: 8) {
                    Text(nav.title)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.heading)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: String(format: "%02d / %02d", nav.position, nav.total))
                        .font(.system(size: 12 * metaUnit).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("시리즈 \(nav.title) — \(nav.position)/\(nav.total)")

            // 진행 스테퍼 — 현재 회차까지 채움. 너무 긴 시리즈는 칸이 실이 되니 생략.
            if nav.total <= 24 {
                HStack(spacing: 3) {
                    ForEach(0..<nav.total, id: \.self) { index in
                        Capsule()
                            .fill(index < nav.position ? Palette.accentMarker : Palette.hairlineStrong)
                            .frame(height: 3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 10)
                .accessibilityHidden(true)
            }

            Button {
                toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("이 시리즈의 글")
                        .font(.system(size: 13 * metaUnit, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10 * metaUnit, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(expanded ? Palette.link : Palette.secondary)
                .expandTapTarget()
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityLabel(expanded ? Text("회차 목록 접기") : Text("회차 목록 펼치기"))

            if expanded {
                episodeList
                    .padding(.top, 8)
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.accentMarker)
                .frame(width: 2.5)
        }
    }

    @ViewBuilder
    private var episodeList: some View {
        if let episodes {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    if episode.slug == currentSlug {
                        episodeRow(index: index, title: episode.title, current: true)
                    } else {
                        NavigationLink(value: Route.post(username: username, slug: episode.slug)) {
                            episodeRow(index: index, title: episode.title, current: false)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
        } else if loadFailed {
            Text("목록을 불러오지 못했습니다")
                .font(.system(size: 13 * metaUnit))
                .foregroundStyle(Palette.secondary)
                .padding(.vertical, 6)
        } else {
            ProgressView()
                .tint(Palette.accent)
                .padding(.vertical, 6)
        }
    }

    private func episodeRow(index: Int, title: String, current: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: String(format: "%02d", index + 1))
                .font(.system(size: 11 * metaUnit).monospacedDigit())
                .foregroundStyle(current ? Palette.link : Palette.secondary)
            Text(title)
                .font(.system(size: 13 * metaUnit, weight: current ? .semibold : .regular))
                .foregroundStyle(current ? Palette.link : Palette.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityLabel(current ? Text("\(index + 1)편 — \(title), 현재 글") : Text("\(index + 1)편 — \(title)"))
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            expanded.toggle()
        }
        guard expanded, episodes == nil else { return }
        Task {
            do {
                let detail = try await BlogAPI.seriesDetail(username: username, slug: nav.slug)
                episodes = detail.posts
            } catch {
                loadFailed = true
            }
        }
    }
}

/// 글 끝의 시리즈 연결 — 완독 직후가 다음 편으로 넘어가는 자연스러운 순간이라,
/// 상단 배너가 갖지 못한 "이어서 읽기"를 여기 카드 하나에 몰아준다. 마지막 편이면
/// 전체 보기 링크만 남는다(웹 SeriesNext 와 같은 규칙).
struct SeriesNextCard: View {
    let nav: PostSeriesNav
    let username: String

    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Hairline()
                .padding(.bottom, 6)

            if let next = nav.next {
                NavigationLink(value: Route.post(username: username, slug: next.slug)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("다음 편")
                            .typeScale(.eyebrow)
                            .foregroundStyle(Palette.link)
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: String(format: "%02d", nav.position + 1))
                                    .font(.system(size: 12 * metaUnit).monospacedDigit())
                                    .foregroundStyle(Palette.secondary)
                                Text(next.title)
                                    .typeScale(.titleSmall)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16 * metaUnit, weight: .medium))
                                .foregroundStyle(Palette.faint)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous)
                            .stroke(Palette.cardBorder, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous))
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityLabel("다음 편 — \(next.title)")
            }

            NavigationLink(value: Route.series(username: username, slug: nav.slug)) {
                Text("시리즈 전체 보기 (\(nav.total)편)")
                    .font(.system(size: 13 * metaUnit))
                    .foregroundStyle(Palette.secondary)
                    .expandTapTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }
}
