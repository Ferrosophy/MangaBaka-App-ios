#if DEBUG && targetEnvironment(simulator)
import Foundation

enum DiscoveryFixtures {
    static func data(path: String, items: [URLQueryItem]) throws -> Data {
        var cards: [[String: Any]] = [
            ["id": 1677, "title": "Chainsaw Man", "native_title": "チェンソーマン", "content_rating": "suggestive", "titles": [["language": "en", "title": "Chainsaw Man"], ["language": "zh-Hans", "title": "电锯人"]]],
            ["id": 1078, "title": "Fire Punch", "native_title": "ファイアパンチ", "content_rating": "suggestive"],
            ["id": 9999, "title": "Hidden example", "content_rating": "erotica"]
        ]
        if let url = Bundle.main.url(forResource: "v1-series-1677-1", withExtension: "json"), let data = try? Data(contentsOf: url), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let row = root["data"] as? [String: Any] {
            cards[0]["cover"] = row["cover"]
        }
        let next: Any = (items.first { $0.name == "page" }?.value ?? "1") == "1" ? 2 : NSNull()
        var root: [String: Any] = ["pagination": ["next": next], "data": cards]
        if path == "v2/news" { root["data"] = [["id": 1, "source_name": "ann", "title": "New manga releases this week", "author": "Review fixture", "published_at": "2026-10-23", "url": "https://www.animenewsnetwork.com/", "mentioned_series": [1677, 1078, 9999], "series": cards]] }
        else if path == "v1/tags" { root["data"] = [["id": 1, "name": "Action"], ["id": 2, "name": "Comedy"]] }
        else if path.contains("/mix") { root["data"] = cards.map { ["series": $0] }; root["dna"] = [["tag_id": 1, "name": "Action", "weight": 0.8]] }
        else if path.hasPrefix("v1/series/") { root["data"] = cards[0] }
        return try JSONSerialization.data(withJSONObject: root)
    }
}
#endif
