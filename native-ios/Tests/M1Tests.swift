import XCTest
@testable import MangaBakaNative

final class M1Tests: XCTestCase {
    func testTrendingQuery() {
        let url = HomeService.requestURL(.trending, type: "manhwa", days: 30)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "sort_by", value: "trending_30d")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "type", value: "manhwa")))
        XCTAssertFalse(HomeService.requestURL(.trending, type: "", days: 7).absoluteString.contains("type="))
    }
    func testUpcomingParsing() {
        let card = HomeCard.parse(["id": 7, "series_id": 12, "sub_title": "Volume", "release_date": "2026-10-27", "sequence_string": "2", "images": [["image": ["x250": ["x1": "https://example.com/a.jpg"]]]]], shelf: .upcoming)
        XCTAssertEqual(card?.link?.absoluteString, "https://mangabaka.org/12")
        XCTAssertEqual(card?.volume, "2")
        XCTAssertNotNil(card?.date)
        XCTAssertNotNil(card?.image)
    }
    func testTitlesAndMissingFields() {
        let card = HomeCard.parse(["id": 3, "title": "Default", "titles": [["language": "en", "title": "English"], ["language": "zh-Hans", "title": "中文"]]], shelf: .trending)!
        XCTAssertEqual(card.displayTitle(locale: Locale(identifier: "zh-Hans")), "中文")
        XCTAssertEqual(card.displayTitle(locale: Locale(identifier: "en")), "English")
        XCTAssertNil(card.image)
        XCTAssertNil(HomeCard.parse([:], shelf: .trending))
    }
    func testPreferencesPersist() {
        let name = "M1Tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.language = "zh-Hans"; preferences.appearance = "dark"
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.language, "zh-Hans")
        XCTAssertEqual(restored.appearance, "dark")
    }
    func testLocalizedStrings() {
        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!).text("Home"), "Home")
        XCTAssertEqual(String(localized: "Home", locale: Locale(identifier: "zh-Hans")), "首页")
    }
}
