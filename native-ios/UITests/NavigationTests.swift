import XCTest

final class NavigationTests: XCTestCase {
    func testEnglishNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        capture("Home-English")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Coming in a future update"].exists)
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 5))
        capture("Settings-English")
    }
    func testChineseNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "zh-Hans"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
        capture("Home-Chinese")
        app.tabBars.buttons["我的"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["语言"].waitForExistence(timeout: 5))
        capture("Settings-Chinese")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
