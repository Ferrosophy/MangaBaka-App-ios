import XCTest

final class DetailNavigationTests: XCTestCase {
    func testEnglishDetailTabs() { review(language: "en", chinese: false) }
    func testChineseDetailTabs() { review(language: "zh-Hans", chinese: true) }
    private func review(language: String, chinese: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-language", language]
        app.launchEnvironment = ["M2_DETAIL": "1677", "M2_FIXTURES": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["detail-tab-Info"].firstMatch.waitForExistence(timeout: 15))
        let tabs = app.scrollViews["detail-tabs"].firstMatch
        for tab in ["Info", "Covers", "Related", "Similar", "News", "Collections", "Works"] {
            let button = app.buttons["detail-tab-" + tab].firstMatch
            for _ in 0..<5 {
                if button.isHittable { break }
                tabs.swipeLeft()
            }
            XCTAssertTrue(button.isHittable, "Missing tab: " + tab)
            button.tap()
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "M2-" + language + "-" + tab
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
