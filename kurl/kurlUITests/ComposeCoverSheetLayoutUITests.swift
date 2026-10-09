//
//  ComposeCoverSheetLayoutUITests.swift
//  kurlUITests
//
//  '글 정보' 시트의 커버 카드·태그 칩 — 빈 타일에서 "본문 첫 이미지를 커버로" 칩이 추가 라벨과 겹치지 않고,
//  커버가 있으면 "변경"이 실제로 눌리는 자리에 있어 사진 바꾸기·커버 제거로 이어지며, 대표 태그 칩 글자가
//  라이트·다크 모두 WCAG AA(4.5:1)를 넘는다. 대비는 화면 픽셀에서 잰다(버튼 비활성 흐림까지 잡히게).
//

import XCTest

final class ComposeCoverSheetLayoutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.appearance = .light
    }

    private func launch(bodyImage: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "legacy", "--reset-recovery"]
            + (bodyImage ? ["--published-body-image"] : [])
        app.launch()
        let manage = app.buttons["발행된 목 글 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "스튜디오에 발행된 목 글이 없음")
        manage.tap()
        app.buttons["편집"].tap()
        return app
    }

    private func openInfoSheet(_ app: XCUIApplication) {
        let more = app.buttons["더 보기"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "더 보기 메뉴가 없음")
        more.tap()
        let info = app.buttons["글 정보…"]
        XCTAssertTrue(info.waitForExistence(timeout: 4), "더 보기 메뉴에 글 정보가 없음")
        info.tap()
        XCTAssertTrue(app.navigationBars["글 정보"].waitForExistence(timeout: 5), "글 정보 시트가 안 뜸")
    }

    private func labeled(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testSuggestionChipSitsBelowTheAddLabelInsteadOfOverIt() throws {
        let app = launch(bodyImage: true)
        openInfoSheet(app)

        let add = app.buttons["커버 이미지 추가"]
        let chip = app.buttons.matching(NSPredicate(format: "label CONTAINS '본문 첫 이미지를 커버로'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "빈 커버 타일이 없음")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "본문 사진이 있는데 커버 제안이 없음")
        XCTAssertFalse(add.frame.intersects(chip.frame), "제안 칩 \(chip.frame) 이 추가 타일 \(add.frame) 과 겹침")
        XCTAssertGreaterThanOrEqual(chip.frame.minY, add.frame.maxY, "제안 칩이 추가 라벨 아래 줄에 있지 않음")
        XCTAssertTrue(chip.isHittable)
        shot("cover-empty-with-suggestion")
    }

    func testChangeChipIsTappableAndRemovingTheCoverSticksAfterSave() throws {
        let app = launch(bodyImage: true)
        openInfoSheet(app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS '본문 첫 이미지를 커버로'")).firstMatch.tap()
        app.buttons["닫기"].tap()
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["저장됨"].waitForExistence(timeout: 10), "제안 커버 저장이 안 돎")

        openInfoSheet(app)
        let change = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == '변경' OR label == '커버 변경'")).firstMatch
        XCTAssertTrue(change.waitForExistence(timeout: 5), "커버가 있는데 변경 칩이 없음")
        XCTAssertTrue(change.isHittable, "변경 칩이 화면에서 눌리지 않는 자리에 있음: \(change.frame)")
        // isHittable 만으로는 잘려 안 보이는 칩도 통과한다(수정 전 코드에서 확인) — 보이는 커버 틀 안에 있어야 한다.
        let cover = app.buttons["커버"]
        XCTAssertTrue(cover.exists, "커버 이미지 영역이 없음")
        XCTAssertTrue(cover.frame.contains(change.frame), "변경 칩 \(change.frame) 이 보이는 커버 틀 \(cover.frame) 밖에 있음")
        let cardTitle = app.staticTexts["composeCardTitle"]
        XCTAssertTrue(cardTitle.exists, "카드 제목이 없음")
        XCTAssertFalse(cover.frame.intersects(cardTitle.frame), "커버 \(cover.frame) 가 카드 제목 \(cardTitle.frame) 을 덮음")
        shot("cover-set-change-chip")

        change.tap()
        XCTAssertTrue(labeled(app, "사진 바꾸기").waitForExistence(timeout: 3), "변경 메뉴에 사진 바꾸기가 없음")
        let remove = labeled(app, "커버 제거")
        XCTAssertTrue(remove.exists, "변경 메뉴에 커버 제거가 없음")
        remove.tap()
        XCTAssertTrue(labeled(app, "커버 이미지 추가").waitForExistence(timeout: 5), "제거해도 카드에 커버가 남음")

        app.buttons["닫기"].tap()
        XCTAssertTrue(app.staticTexts["저장 필요"].waitForExistence(timeout: 5), "라이브 글 커버 제거가 저장할 변경으로 안 보임")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["저장됨"].waitForExistence(timeout: 10), "커버 제거 저장이 안 돎")

        app.navigationBars.buttons.firstMatch.tap()
        let manage = app.buttons["발행된 목 글 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        manage.tap()
        app.buttons["편집"].tap()
        openInfoSheet(app)
        XCTAssertTrue(labeled(app, "커버 이미지 추가").waitForExistence(timeout: 5), "저장한 커버 제거가 다시 열면 풀림")
    }

    func testPrimaryTagChipTextMeetsAAInLightMode() throws {
        try assertPrimaryTagContrast(appearance: .light)
    }

    func testPrimaryTagChipTextMeetsAAInDarkMode() throws {
        try assertPrimaryTagContrast(appearance: .dark)
    }

    private func assertPrimaryTagContrast(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launch(bodyImage: false)
        openInfoSheet(app)
        let chip = app.buttons["대표 태그 회고"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "대표 태그 칩이 없음")
        let ratio = try renderedContrast(of: chip, in: app)
        shot("primary-tag-\(appearance == .dark ? "dark" : "light")-\(String(format: "%.2f", ratio))")
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "대표 태그 글자 대비 \(String(format: "%.2f", ratio)):1 — AA 미달")
    }

    /// 요소 영역의 화면 픽셀에서 가장 흔한 색을 바탕으로, 바탕과 대비가 가장 큰 픽셀을 글자로 보고 WCAG 대비를 잰다.
    private func renderedContrast(of element: XCUIElement, in app: XCUIApplication) throws -> Double {
        let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let f = element.frame
        let rect = CGRect(x: f.minX * scale, y: f.minY * scale, width: f.width * scale, height: f.height * scale)
            .integral
        let crop = try XCTUnwrap(image.cropping(to: rect))
        let width = crop.width, height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)

        func luminance(_ i: Int) -> Double {
            func channel(_ v: UInt8) -> Double {
                let c = Double(v) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(pixels[i]) + 0.7152 * channel(pixels[i + 1]) + 0.0722 * channel(pixels[i + 2])
        }
        var counts: [Int: (count: Int, index: Int)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let key = Int(pixels[i] >> 3) << 10 | Int(pixels[i + 1] >> 3) << 5 | Int(pixels[i + 2] >> 3)
            counts[key, default: (0, i)].count += 1
        }
        let background = luminance(try XCTUnwrap(counts.values.max { $0.count < $1.count }).index)
        var best = 1.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let l = luminance(i)
            best = max(best, (max(l, background) + 0.05) / (min(l, background) + 0.05))
        }
        return best
    }
}
