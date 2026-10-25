import XCTest

final class AccountNavigationTests: XCTestCase {
    func testEnglishAccountOnlyLibrary() { check(language: "en", library: "Library", profile: "Profile", signIn: "Sign in") }
    func testChineseAccountOnlyLibrary() { check(language: "zh-Hans", library: "书库", profile: "我的", signIn: "登录") }
    private func check(language: String, library: String, profile: String, signIn: String) {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-language", language]; app.launchArguments += ["-startPage", "0"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons[library].waitForExistence(timeout: 10)); app.tabBars.buttons[library].tap()
        XCTAssertTrue(app.buttons[signIn].waitForExistence(timeout: 5)); capture("M3-\(language)-Library-sign-in")
        app.tabBars.buttons[profile].tap()
        XCTAssertTrue(app.buttons[signIn].waitForExistence(timeout: 5)); capture("M3-\(language)-Profile-sign-in")
    }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
}
