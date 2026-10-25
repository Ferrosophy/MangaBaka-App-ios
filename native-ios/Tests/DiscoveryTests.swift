import XCTest
@testable import MangaBakaNative

final class DiscoveryTests: XCTestCase {
    func testBrowseFiltersAndStableRandom() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = Preferences(defaults: defaults)
        let query = BrowseQuery(type: "oel-other", status: "completed", tag: "123", sort: "random", randomSeed: 0.25)
        let a = query.items(page: 1, preferences: preferences, account: nil)
        let b = query.items(page: 2, preferences: preferences, account: nil)
        XCTAssertEqual(a.filter { $0.name == "type" }.compactMap(\.value), ["oel", "other"])
        XCTAssertEqual(a.first { $0.name == "random_seed" }, b.first { $0.name == "random_seed" })
        XCTAssertTrue(a.contains(URLQueryItem(name: "tag", value: "123")))
        XCTAssertFalse(a.contains { $0.name == "exclude_user_library" })
        preferences.hideLibrary = true
        XCTAssertTrue(query.items(page: 1, preferences: preferences, account: "owner").contains(URLQueryItem(name: "exclude_user_library", value: "owner")))
    }
    func testReadinessDoesNotBlockStaleProfile() throws {
        let state = try RecommendationReadiness.decode(Data(#"{"cold_start":false,"profile_stale":true,"library_count":7}"#.utf8))
        XCTAssertFalse(state.cold); XCTAssertTrue(state.stale)
        XCTAssertThrowsError(try RecommendationReadiness.decode(Data(#"{"status":200}"#.utf8)))
    }
    func testLocalSettingsAndAccountDismissals() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let p = Preferences(defaults: defaults)
        XCTAssertEqual(p.visibleRatings, ["safe", "suggestive"])
        XCTAssertFalse(p.allows("erotica")); XCTAssertTrue(p.allows(nil))
        p.startPage = 2; p.titleLanguage = "native"; p.ratingStep = 5; p.dismissSeries("1677", account: "a")
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.startPage, 2); XCTAssertEqual(restored.ratingStep, 5)
        XCTAssertTrue(restored.dismissed("a").contains("1677")); XCTAssertTrue(restored.dismissed("b").isEmpty)
        let card = HomeCard.parse(["id": 1, "title": "English", "native_title": "原文", "content_rating": "safe"], shelf: .trending)!
        XCTAssertEqual(restored.title(card), "原文")
    }
    func testNewsIndependentReferences() {
        let article = NewsArticle(record: DetailRecord(["id": 3, "title": "News", "url": "javascript:alert(1)", "mentioned_series": [1, 2], "series": [["id": 1, "title": "One", "content_rating": "safe"]]]))
        XCTAssertNil(article.url); XCTAssertEqual(article.total, 2); XCTAssertEqual(article.series.count, 1)
    }
    @MainActor func testRefreshAndDeduplication() async throws {
        setenv("M4_FIXTURES", "1", 1); defer { unsetenv("M4_FIXTURES") }
        let list = DiscoveryList()
        await list.load(path: "v2/series/search", items: [])
        XCTAssertEqual(list.cards.count, 3); XCTAssertTrue(list.hasNext)
        await list.load(path: "v2/series/search", items: [])
        XCTAssertEqual(list.cards.count, 3); XCTAssertFalse(list.hasNext)
        list.reset(); XCTAssertTrue(list.cards.isEmpty); XCTAssertFalse(list.loaded)
    }
}
