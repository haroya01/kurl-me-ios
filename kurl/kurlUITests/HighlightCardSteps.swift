import XCTest

extension XCUIApplication {
    /// 칠해진 문장을 탭해 카드를 띄운다. 첫 좌표가 마크를 비껴가면 한 번 더 친다.
    @discardableResult
    func tapHighlight(in paragraph: XCUIElement, at offsets: [CGVector]) -> Bool {
        let card = otherElements["highlightCard"]
        for offset in offsets {
            paragraph.coordinate(withNormalizedOffset: offset).tap()
            if card.waitForExistence(timeout: 4) { return true }
        }
        return false
    }

    /// 카드에서 대화를 연다 — 대화가 달린 행이 있으면 그 행, 없으면 "이 문장에 대해 이야기하기".
    @discardableResult
    func openConversationFromCard() -> Bool {
        let entry = buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'highlightCard.conversation' OR identifier == 'highlightCard.talk'"
        )).firstMatch
        guard entry.waitForExistence(timeout: 4) else { return false }
        entry.tap()
        return navigationBars["대화"].waitForExistence(timeout: 6)
    }
}
