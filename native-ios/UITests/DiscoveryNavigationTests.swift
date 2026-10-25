import XCTest

final class DiscoveryNavigationTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testBrowseNewsMixAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en", "-startPage", "0"]
        app.launchEnvironment["M4_FIXTURES"] = "1"
        app.launch()
        app.tabBars.buttons["Browse"].tap()
        XCTAssertTrue(app.staticTexts["Manga"].waitForExistence(timeout: 5))
        capture("M4-Browse")
        app.buttons["Most popular"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Chainsaw Man"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Hidden example"].exists)
        capture("M4-Ranking")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Mix"].tap()
        XCTAssertTrue(app.staticTexts["Start your mix"].waitForExistence(timeout: 5))
        capture("M4-Mix-empty")
        app.buttons["Add a series…"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Chainsaw")
        let result = app.buttons.containing(.staticText, identifier: "Chainsaw Man").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8)); result.tap()
        XCTAssertTrue(app.staticTexts["Shared traits"].waitForExistence(timeout: 8))
        capture("M4-Mix-results")
        app.tabBars.buttons["News"].tap()
        XCTAssertTrue(app.staticTexts["New manga releases this week"].waitForExistence(timeout: 8))
        capture("M4-News")
        app.buttons["Settings"].tap()
        app.buttons["Content"].tap()
        app.buttons["Content rating preferences"].tap()
        XCTAssertTrue(app.staticTexts["Safe content"].waitForExistence(timeout: 5))
        capture("M4-Content-preferences")
    }
    func testChineseBrowseAndLoggedOutQueue() {
        let app = XCUIApplication(); app.launchArguments = ["-language", "zh-Hans", "-startPage", "2"]
        app.launchEnvironment["M4_FIXTURES"] = "1"; app.launch()
        XCTAssertTrue(app.staticTexts["日漫"].waitForExistence(timeout: 8))
        capture("M4-Browse-Chinese")
        app.buttons["发现队列"].tap()
        XCTAssertTrue(app.buttons["登录"].waitForExistence(timeout: 5))
        capture("M4-Queue-sign-in")
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
