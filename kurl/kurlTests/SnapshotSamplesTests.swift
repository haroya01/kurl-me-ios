//
//  SnapshotSamplesTests.swift
//  kurlTests
//
//  스냅샷 회귀 테스트 샘플(②층). 디자인 시스템(색·타이포)을 픽셀로 고정 → 토큰·스케일이
//  의도치 않게 바뀌면 CI 가 자동으로 빨간불(사람 눈 없이 회귀 감지).
//
//  최초 실행은 레퍼런스 PNG 를 굽고(__Snapshots__/) 일부러 실패한다 — 그 PNG 를 커밋하면
//  이후엔 픽셀 비교(완전일치 아님 — 아래 `snapshot(_:_:)` 의 precision 주석 참고).
//  새로 구우려면 환경변수 `SNAPSHOT_RECORD=1` 또는 PNG 삭제 후 재실행.
//
//  대상은 "종이(§10)" 표면만 — 결정적이라 안 흔들린다. Liquid Glass(glassEffect)·상대시간·
//  네트워크 의존 뷰는 오프스크린 렌더가 비거나 흔들리므로 제외(그 표면은 UITest/수동 레인).
//

import SnapshotTesting
import SwiftUI
import XCTest

@testable import kurl

final class SnapshotSamplesTests: XCTestCase {

    override func invokeTest() {
        let record: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : .missing
        withSnapshotTesting(record: record) { super.invokeTest() }
    }

    private func traits(_ style: UIUserInterfaceStyle, xxxl: Bool = false) -> UITraitCollection {
        var list: [UITraitCollection] = [.init(userInterfaceStyle: style)]
        if xxxl { list.append(.init(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)) }
        return UITraitCollection(traitsFrom: list)
    }

    // 완전일치(precision 1.0)로 굽지 않는다 — 폰트 래스터라이저는 런타임 점릴리스·기기 모델마다
    // 글자·둥근모서리 가장자리 안티에일리어싱을 서브픽셀만큼 다르게 그린다. 그 미세 흔들림까지
    // 회귀로 잡으면 기준 디바이스에서조차 오탐 red 가 난다(런타임 갱신 시). precision 은 어긋난
    // 픽셀 비율 허용치, perceptualPrecision 은 픽셀별 색 근접도 하한이라 — 토큰 색 변경·raw .red
    // 재유입·타입스케일 변경처럼 "많은 픽셀이 크게" 바뀌는 진짜 회귀는 여전히 잡는다.
    private static let pixelPrecision: Float = 0.99
    private static let colorPrecision: Float = 0.98

    private func snapshot<V: View>(_ size: CGSize, _ style: UIUserInterfaceStyle, xxxl: Bool = false) -> Snapshotting<V, UIImage> {
        .image(
            precision: Self.pixelPrecision,
            perceptualPrecision: Self.colorPrecision,
            layout: .fixed(width: size.width, height: size.height),
            traits: traits(style, xxxl: xxxl))
    }

    // MARK: Palette 토큰 스와치 — 색 회귀 감지(raw .red 재유입·토큰값 변경 등)

    private var swatches: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.tokens, id: \.0) { name, color in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Metrics.radiusThumb)
                        .fill(color)
                        .frame(width: 48, height: 30)
                    Text(name).typeScale(.body).foregroundStyle(Palette.ink)
                }
            }
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(Palette.pageBg)
    }

    private static let tokens: [(String, Color)] = [
        ("ink", Palette.ink),
        ("secondary", Palette.secondary),
        ("faint", Palette.faint),
        ("accent (600)", Palette.accent),
        ("link (700)", Palette.link),
        ("danger", Palette.danger),
    ]

    func test_paletteSwatches_light() {
        assertSnapshot(of: swatches, as: snapshot(CGSize(width: 320, height: 280), .light))
    }

    func test_paletteSwatches_dark() {
        assertSnapshot(of: swatches, as: snapshot(CGSize(width: 320, height: 280), .dark))
    }

    // MARK: 타입 사다리 — 타이포 회귀 감지(typeScale 우회·사다리값 변경). XXXL 은 Dynamic Type 검증.

    private var typeLadder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("featured · 가나다 Aa").typeScale(.featured)
            Text("title · 가나다 Aa").typeScale(.title)
            Text("titleSmall · 가나다").typeScale(.titleSmall)
            Text("lede · 가나다 Aa").typeScale(.lede)
            Text("body · 가나다 Aa").typeScale(.body)
            Text("meta · 가나다").typeScale(.meta)
            Text("eyebrow · 가나다").typeScale(.eyebrow)
        }
        .foregroundStyle(Palette.ink)
        .frame(width: 360, alignment: .leading)
        .padding(20)
        .background(Palette.pageBg)
    }

    func test_typeLadder_light() {
        assertSnapshot(of: typeLadder, as: snapshot(CGSize(width: 360, height: 360), .light))
    }

    func test_typeLadder_dark() {
        assertSnapshot(of: typeLadder, as: snapshot(CGSize(width: 360, height: 360), .dark))
    }

    func test_typeLadder_dynamicTypeXXXL() {
        assertSnapshot(of: typeLadder, as: snapshot(CGSize(width: 360, height: 620), .light, xxxl: true))
    }
}
