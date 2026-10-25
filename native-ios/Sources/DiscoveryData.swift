import Foundation
import Observation

struct BrowseQuery: Equatable {
    var text = ""
    var type = ""
    var status = ""
    var tag = ""
    var sort = "popularity_asc"
    var randomSeed = Double.random(in: 0..<1)
    func items(page: Int, preferences: Preferences, account: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "schema", value: "full"), URLQueryItem(name: "sort_by", value: sort)]
        for (key, value) in [("q", text), ("status", status), ("tag", tag)] where !value.isEmpty { items.append(URLQueryItem(name: key, value: value)) }
        for t in type == "oel-other" ? ["oel", "other"] : (type.isEmpty ? [] : [type]) { items.append(URLQueryItem(name: "type", value: t)) }
        items += preferences.visibleRatings.map { URLQueryItem(name: "content_rating", value: $0) }
        if sort == "random" { items.append(URLQueryItem(name: "random_seed", value: String(randomSeed))) }
        if preferences.hideLibrary, let account { items.append(URLQueryItem(name: "exclude_user_library", value: account)) }
        return items
    }
}
actor DiscoveryAPI {
    static let shared = DiscoveryAPI()
    private var cache: [URL: Data] = [:]
    nonisolated static func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        var c = URLComponents(string: "https://api.mangabaka.org/" + path)!
        c.queryItems = items; return c.url!
    }
    func get(_ path: String, items: [URLQueryItem] = [], refresh: Bool = false) async throws -> Data {
        let url = Self.url(path, items)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["M4_FIXTURES"] == "1" { return try DiscoveryFixtures.data(path: path, items: items) }
        #endif
        if !refresh, let data = cache[url] { return data }
        var request = URLRequest(url: url); request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        _ = try JSONSerialization.jsonObject(with: data)
        if cache.count > 100 { cache.removeAll() }; cache[url] = data
        return data
    }
}
@MainActor @Observable final class DiscoveryList {
    var rows: [DetailRecord] = []
    var dna: [DetailRecord] = []
    var loading = false
    var failed = false
    var loaded = false
    var hasNext = false
    private var page = 1
    private var generation = UUID()
    func reset() { generation = UUID(); rows = []; dna = []; page = 1; loaded = false; hasNext = false; loading = false; failed = false }
    func load(path: String, items: [URLQueryItem], refresh: Bool = false) async {
        if loading && !refresh { return }
        let token = UUID(); generation = token; loading = true; failed = false
        let requested = refresh ? 1 : page
        do {
            let data = try await DiscoveryAPI.shared.get(path, items: items.filter { $0.name != "page" } + [URLQueryItem(name: "page", value: String(requested))], refresh: refresh)
            let result = try DetailPage.decode(data)
            guard token == generation else { return }
            rows = DetailPage.unique((refresh ? [] : rows) + result.records)
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            dna = (root?["dna"] as? [[String: Any]] ?? []).map(DetailRecord.init)
            page = requested + 1; hasNext = result.hasNext; loaded = true; loading = false
        } catch { if token == generation { failed = true; loading = false } }
    }
    var cards: [HomeCard] { rows.compactMap { $0.object("series").card ?? $0.card } }
}
struct NewsArticle: Identifiable {
    let record: DetailRecord
    var id: String { record.id }
    var series: [HomeCard] { record.records("series").compactMap(\.card) }
    var total: Int { (record.values["mentioned_series"] as? [Any])?.count ?? series.count }
    var url: URL? { guard let u = URL(string: record.text("url")), ["https", "http"].contains(u.scheme ?? "") else { return nil }; return u }
}
