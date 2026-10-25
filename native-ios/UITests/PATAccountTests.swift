import XCTest

final class PATAccountTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testPATFormRejectsInvalidInputAndCancels() {
        let app = launch(language: "en")
        app.tabBars.buttons["Library"].tap(); app.buttons["Sign in"].tap()
        XCTAssertTrue(app.secureTextFields["pat-input"].waitForExistence(timeout: 5))
        let input = app.secureTextFields["pat-input"]; input.tap(); input.typeText("invalid")
        app.buttons["pat-connect"].tap()
        XCTAssertTrue(app.staticTexts["pat-error"].waitForExistence(timeout: 5))
        capture("M3-PAT-validation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Sign in"].exists)
    }
    func testPATLibraryProgressRatingAndStatistics() {
        executionTimeAllowance = 240
        let app = launch(language: "en")
        connect(app, library: "Library", signIn: "Sign in")
        XCTAssertTrue(app.staticTexts["Review Series"].firstMatch.waitForExistence(timeout: 10)); capture("M3-PAT-Library")
        app.buttons["library-status-completed"].tap()
        let book = app.buttons["library-entry-1677"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        let chapters = app.buttons["edit-Update chapters"].firstMatch
        XCTAssertTrue(chapters.waitForExistence(timeout: 10))
        if !chapters.isHittable { app.swipeUp() }; chapters.tap()
        let field = app.textFields["reading-value"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "231")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["231 / 232"].waitForExistence(timeout: 8))
        let rating = app.buttons["edit-rating"].firstMatch
        if !rating.isHittable { app.swipeUp() }; rating.tap()
        XCTAssertTrue(app.buttons["Clear rating"].waitForExistence(timeout: 5)); app.buttons["Clear rating"].tap()
        XCTAssertTrue(app.staticTexts["Not rated"].waitForExistence(timeout: 8)); capture("M3-PAT-Reading-record")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Simulator Review"].waitForExistence(timeout: 5)); capture("M3-PAT-Profile")
        app.buttons["Full statistics"].tap()
        XCTAssertTrue(app.staticTexts["Reading overview"].waitForExistence(timeout: 5)); capture("M3-PAT-Statistics")
    }
    func testChinesePATConnection() {
        let app = launch(language: "zh-Hans")
        connect(app, library: "书库", signIn: "登录")
        XCTAssertTrue(app.staticTexts["Review Series"].firstMatch.waitForExistence(timeout: 10)); capture("M3-PAT-Chinese-Library")
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["Simulator Review"].waitForExistence(timeout: 5)); capture("M3-PAT-Chinese-Profile")
    }
    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["-language", language]
        app.launchEnvironment = ["M3_ACCOUNT_FIXTURES": "1", "M2_FIXTURES": "1"]
        app.launchArguments += ["-startPage", "0"]; app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10)); return app
    }
    private func connect(_ app: XCUIApplication, library: String, signIn: String) {
        app.tabBars.buttons[library].tap(); app.buttons[signIn].tap()
        let input = app.secureTextFields["pat-input"]; XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("mb-simulator-review"); app.buttons["pat-connect"].tap()
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
