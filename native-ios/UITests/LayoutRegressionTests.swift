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
        func drawerHeight() -> CGFloat {
            let field = app.searchFields.firstMatch
            return field.exists && field.isHittable ? field.frame.height + 16 : 0
        }
        let initialDrawer = drawerHeight()
        let scroll = app.scrollViews.firstMatch
        for attempt in 1...2 {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
            // Pulling down legitimately reveals the native navigation search drawer.
            // Subtract its measured height, but reject any additional refresh inset.
            let settled = NSPredicate { _, _ in one.exists && abs(one.frame.minY - baseline - (drawerHeight() - initialDrawer)) < 20 }
            expectation(for: settled, evaluatedWith: nil); waitForExpectations(timeout: 12)
            capture("Layout-Refresh-settled-\(attempt)")
        }
    }
    func testRelatedScoresTabsAndTranslationConfiguration() {
        executionTimeAllowance = 240
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
        let tabs = app.scrollViews["detail-tabs"].firstMatch
        for tab in ["Covers", "Similar", "Works"] {
            let button = app.buttons["detail-tab-" + tab].firstMatch
            if tab == "Covers" { tabs.swipeRight() }
            for _ in 0..<8 {
                if button.frame.minX >= tabs.frame.minX && button.frame.maxX <= tabs.frame.maxX { break }
                tabs.swipeLeft()
            }
            button.tap()
            let prefix = tab == "Covers" ? "cover-card-" : (tab == "Works" ? "work-cover-" : "series-card-")
            let grid = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            XCTAssertTrue(grid.firstMatch.waitForExistence(timeout: 8))
            if tab == "Works", grid.firstMatch.frame.width > app.frame.width * 0.6 { app.buttons["Change layout"].firstMatch.tap() }
            if grid.count >= 2 {
                XCTAssertEqual(grid.element(boundBy: 0).frame.width, grid.element(boundBy: 1).frame.width, accuracy: 1)
                XCTAssertEqual(grid.element(boundBy: 0).frame.height, grid.element(boundBy: 1).frame.height, accuracy: 1)
            }
            capture("Layout-" + tab + "-grid-aligned")
        }
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
    func testOnlyOneAddToLibraryMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en", "-startPage", "0"]
        app.launchEnvironment = ["M2_DETAIL": "1677", "M2_FIXTURES": "1", "M3_ACCOUNT_FIXTURES": "1", "M4_LAYOUT_REVIEW": "1"]
        app.launch()
        let signIn = app.buttons["Sign in to add to library"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10)); signIn.tap()
        let input = app.secureTextFields["pat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("mb-simulator-review"); app.buttons["pat-connect"].tap()
        let add = app.buttons["Add to library"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "Add to library").count, 1)
        add.tap()
        XCTAssertTrue(app.buttons["Plan to read"].waitForExistence(timeout: 5))
        capture("Layout-Single-Add-Menu")
    }
    func testAccessibilitySizeBrowse() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "zh-Hans", "-startPage", "2", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment = ["M4_FIXTURES": "1", "M4_LAYOUT_REVIEW": "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["日漫"].waitForExistence(timeout: 8))
        capture("Layout-Chinese-Accessibility-text")
        let rank = app.buttons["最受欢迎"].firstMatch
        if !rank.isHittable { app.swipeUp() }; rank.tap()
        let first = app.buttons["discovery-card-101"], second = app.buttons["discovery-card-102"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(first.frame.width, 140)
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        capture("Layout-Chinese-Accessibility-grid")
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
