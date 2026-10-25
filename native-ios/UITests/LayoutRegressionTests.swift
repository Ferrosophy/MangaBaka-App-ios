import XCTest

final class LayoutRegressionTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testGridFillRefreshAndDarkLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en", "-appearance", "dark", "-startPage", "2"]
        app.launchEnvironment = ["M4_FIXTURES": "1", "M4_LAYOUT_REVIEW": "1"]
        app.launch()
        app.buttons["Most popular"].firstMatch.tap()
        let one = app.buttons["discovery-card-101"], two = app.buttons["discovery-card-102"], three = app.buttons["discovery-card-103"]
        XCTAssertTrue(one.waitForExistence(timeout: 8)); XCTAssertTrue(two.exists); XCTAssertTrue(three.exists)
        XCTAssertEqual(one.frame.width, two.frame.width, accuracy: 1)
        XCTAssertEqual(one.frame.height, two.frame.height, accuracy: 1)
        XCTAssertEqual(one.frame.height, three.frame.height, accuracy: 1)
        XCTAssertEqual(one.frame.minY, two.frame.minY, accuracy: 1)
        capture("Layout-Ranking-portrait-landscape-square-missing-Dark")
        let baseline = one.frame.minY
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        let settled = NSPredicate { _, _ in one.exists && abs(one.frame.minY - baseline) < 20 }
        expectation(for: settled, evaluatedWith: nil); waitForExpectations(timeout: 12)
        capture("Layout-Refresh-settled")
    }
    func testRelatedScoresTabsAndTranslationConfiguration() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en", "-appearance", "light", "-startPage", "0"]
        app.launchEnvironment = ["M2_DETAIL": "1677", "M2_FIXTURES": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["source-score-anilist"].waitForExistence(timeout: 10))
        let translate = app.buttons["translate-description"]
        if !translate.isHittable { app.swipeUp() }
        XCTAssertTrue(translate.waitForExistence(timeout: 5)); capture("Layout-Scores-Description-Light")
        translate.tap()
        XCTAssertTrue(app.navigationBars["Translation settings"].waitForExistence(timeout: 5))
        capture("Translation-Configuration")
        app.buttons["Done"].tap()
        let related = app.buttons["detail-tab-Related"]
        if !related.isHittable { app.swipeDown() }
        XCTAssertTrue(related.waitForExistence(timeout: 5)); related.tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "series-card-"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 8))
        if cards.count >= 2 {
            XCTAssertEqual(cards.element(boundBy: 0).frame.width, cards.element(boundBy: 1).frame.width, accuracy: 1)
            XCTAssertEqual(cards.element(boundBy: 0).frame.height, cards.element(boundBy: 1).frame.height, accuracy: 1)
        }
        capture("Layout-Related-aligned")
    }
    func testProfileShelvesAndLibraryHaveEqualCards() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en", "-appearance", "light", "-startPage", "1"]
        app.launchEnvironment = ["M3_ACCOUNT_FIXTURES": "1", "M4_LAYOUT_REVIEW": "1"]
        app.launch(); app.buttons["Sign in"].tap()
        let token = app.secureTextFields["pat-input"]
        XCTAssertTrue(token.waitForExistence(timeout: 5)); token.tap(); token.typeText("mb-simulator-review"); app.buttons["pat-connect"].tap()
        let first = app.buttons["library-entry-101"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let second = app.buttons["library-entry-102"]
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        capture("Layout-Library-progress-and-title-slots")
        app.tabBars.buttons["Profile"].tap(); app.swipeUp()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "snapshot-Recently changed-"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(cards.element(boundBy: 0).frame.width, cards.element(boundBy: 1).frame.width, accuracy: 1)
        XCTAssertEqual(cards.element(boundBy: 0).frame.height, cards.element(boundBy: 1).frame.height, accuracy: 1)
        capture("Layout-Profile-Shelves-aligned")
        let shelves = app.scrollViews.containing(.button, identifier: cards.firstMatch.identifier).allElementsBoundByIndex
        if let shelf = shelves.last { shelf.swipeLeft(); shelf.swipeRight() }
        XCTAssertGreaterThanOrEqual(cards.firstMatch.frame.minX, 12)
        capture("Layout-Profile-Shelf-left-edge")
    }
    func testAccessibilitySizeBrowse() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "zh-Hans", "-startPage", "2", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment = ["M4_FIXTURES": "1", "M4_LAYOUT_REVIEW": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["日漫"].waitForExistence(timeout: 8))
        capture("Layout-Chinese-Accessibility-text")
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
