import XCTest
@testable import MangaBakaNative

final class DetailTests: XCTestCase {
    func testScoreExcludesMissingAndNonFinite() {
        let s = DetailRecord(["source": ["a": ["rating_normalized": 80], "b": ["rating_normalized": "90"], "c": ["rating_normalized": "NaN"], "d": [:]]])
        XCTAssertEqual(s.score, 85)
        XCTAssertNil(DetailRecord([:]).score)
    }
    func testImagesRejectInvalidAndTryAllWorkImages() {
        let r = DetailRecord(["images": [["image": ["raw": ["url": ""]]], ["image": ["x250": ["x1": "https://example.org/2.jpg"], "raw": ["url": "https://example.org/raw.jpg"]]]]])
        XCTAssertEqual(r.workImages.count, 2)
        XCTAssertTrue(ImageCandidates.urls("file:///tmp/a").isEmpty)
    }
    func testDuplicateVolumeNumbersArePreserved() {
        let rows = [DetailRecord(["id": 1, "sequence_string": "1"]), DetailRecord(["id": 2, "sequence_string": "1"]), DetailRecord(["id": 1, "sequence_string": "1"])]
        XCTAssertEqual(DetailPage.unique(rows).map(\.id), ["1", "2"])
    }
    func testPaginationAndEmptyResponse() throws {
        let page = try DetailPage.decode(Data(#"{"data":[],"pagination":{"next":null}}"#.utf8))
        XCTAssertFalse(page.hasNext)
        XCTAssertTrue(page.records.isEmpty)
        XCTAssertThrowsError(try DetailPage.decode(Data(#"{"data":{}}"#.utf8)))
    }
    func testHomepageUsesSeriesIDForUpcoming() {
        let card = HomeCard.parse(["id": 100, "series_id": 1677, "sub_title": "Vol 1"], shelf: .upcoming)
        XCTAssertEqual(card?.seriesID, "1677")
    }
    func testHierarchicalTags() {
        let groups = ResolvedTagGroup.resolve(names: ["Mafia", "Unknown tag"], paths: ["mafia": "Activities > Crimes > Organized Crime > Mafia"])
        XCTAssertEqual(groups.first?.title, "Activities")
        XCTAssertEqual(groups.first?.subgroups["Crimes"], ["Organized Crime > Mafia"])
        XCTAssertEqual(groups.last?.title, "Other")
    }
    func testCapturedSeriesResponse() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "v1-series-1677-1", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let series = DetailRecord(try XCTUnwrap(root["data"] as? [String: Any]))
        XCTAssertEqual(series.id, "1677")
        XCTAssertNotNil(series.card)
    }
}
