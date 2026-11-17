import XCTest

final class EnglishPracticeUITests: XCTestCase {
    func testOriginalDemoOpens() {
        let app = XCUIApplication()
        app.launch()
        let title = app.staticTexts["每日英语练习"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "原文阅读").firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "随机抽题").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["useful"].firstMatch.waitForExistence(timeout: 5))
    }
}
