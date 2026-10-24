import XCTest

final class DetailNavigationTests: XCTestCase {
    func testEnglishDetailTabs() { review(language: "en", chinese: false) }
    func testChineseDetailTabs() { review(language: "zh-Hans", chinese: true) }
    func testCollectionDirectoryAndPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en"]
        app.launchEnvironment = ["M2_DETAIL": "1677", "M2_FIXTURES": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["detail-tab-Info"].firstMatch.waitForExistence(timeout: 15))
        let tabs = app.scrollViews["detail-tabs"].firstMatch
        app.buttons["Preview cover"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["gallery-loaded-image"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        selectTab("Collections", app: app, tabs: tabs)
        let collection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection-")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        collection.tap()
        let work = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "work-cover-")).firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        let directory = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        directory.name = "M2-Collection-directory"; directory.lifetime = .keepAlways; add(directory)
        work.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["gallery-loaded-image"].firstMatch.waitForExistence(timeout: 20))
        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "M2-Cover-preview"; preview.lifetime = .keepAlways; add(preview)
        app.buttons["Done"].tap()
    }
    private func selectTab(_ tab: String, app: XCUIApplication, tabs: XCUIElement) {
        let button = app.buttons["detail-tab-" + tab].firstMatch
        for _ in 0..<8 {
            let frame = button.frame
            let viewport = tabs.frame
            if frame.width > 0 && frame.minX >= viewport.minX && frame.maxX <= viewport.maxX {
                button.tap()
                return
            }
            tabs.swipeLeft()
        }
        XCTFail("Tab could not be scrolled into view: " + tab)
    }
    private func review(language: String, chinese: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-language", language]
        app.launchEnvironment = ["M2_DETAIL": "1677", "M2_FIXTURES": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["detail-tab-Info"].firstMatch.waitForExistence(timeout: 15))
        let tabs = app.scrollViews["detail-tabs"].firstMatch
        for tab in ["Info", "Covers", "Related", "Similar", "News", "Collections", "Works"] {
            selectTab(tab, app: app, tabs: tabs)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "M2-" + language + "-" + tab
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
