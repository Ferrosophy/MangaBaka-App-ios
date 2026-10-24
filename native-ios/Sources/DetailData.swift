import Foundation
import Observation

struct DetailRecord: Identifiable {
    let values: [String: Any]
    var id: String { text("id").isEmpty ? [text("title"), text("type"), text("language"), text("index"), text("url")].joined(separator: "|") : text("id") }
    init(_ values: [String: Any]) { self.values = values }
    func text(_ key: String) -> String { guard let v = values[key], !(v is NSNull) else { return "" }; return String(describing: v) }
    func object(_ key: String) -> DetailRecord { DetailRecord(values[key] as? [String: Any] ?? [:]) }
    func records(_ key: String) -> [DetailRecord] { (values[key] as? [[String: Any]] ?? []).map(DetailRecord.init) }
    func names(_ key: String) -> String {
        if let rows = values[key] as? [String] { return rows.joined(separator: ", ") }
        return records(key).map { $0.text("name").isEmpty ? $0.text("title") : $0.text("name") }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    var card: HomeCard? { HomeCard.parse(values, shelf: .trending) }
    var cover: URL? { HomeCard.imageURL(values["cover"] ?? values["cover_image"]) }
    var sourceScores: [(name: String, score: Double, url: URL?)] {
        let sources = values["source"] as? [String: [String: Any]] ?? [:]
        return sources.keys.sorted().compactMap { key in
            guard let row = sources[key], let score = Double(HomeCard.string(row["rating_normalized"])), score.isFinite else { return nil }
            return (key, score, URL(string: row["url"] as? String ?? ""))
        }
    }
    var score: Double? { let scores = sourceScores.map(\.score); return scores.isEmpty ? nil : scores.reduce(0,+) / Double(scores.count) }
    var coverCandidates: [URL] {
        let raw = values["image"] ?? values["cover"] ?? values["cover_image"]
        return ImageCandidates.urls(raw)
    }
    var workImages: [URL] { records("images").flatMap(\.coverCandidates) }
}
enum ImageCandidates {
    static func urls(_ raw: Any?) -> [URL] {
        if let s = raw as? String, let url = URL(string: s), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return [url] }
        guard let map = raw as? [String: Any] else { return [] }
        return ["x350", "x250", "x150", "raw", "url", "x1", "x2"].flatMap { urls(map[$0]) }.reduce(into: []) { result, url in if !result.contains(url) { result.append(url) } }
    }
}
enum DetailTab: String, CaseIterable, Identifiable {
    case info = "Info", covers = "Covers", related = "Related", similar = "Similar", news = "News", collections = "Collections", works = "Works"
    var id: String { rawValue }
    var resource: String { switch self { case .info: "links"; case .covers: "images"; case .related: "relationships"; case .similar: "similar"; case .news: "news"; case .collections: "collections"; case .works: "works" } }
}
struct DetailPage {
    var records: [DetailRecord]
    var hasNext: Bool
    static func decode(_ data: Data) throws -> DetailPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = (root["data"] ?? root["results"]) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        let next = (root["pagination"] as? [String: Any])?["next"]
        return DetailPage(records: rows.map(DetailRecord.init), hasNext: next != nil && !(next is NSNull) && (next as? Bool != false))
    }
    static func unique(_ rows: [DetailRecord]) -> [DetailRecord] {
        var ids = Set<String>(); return rows.filter { ids.insert($0.id).inserted }
    }
}
actor DetailAPI {
    static let shared = DetailAPI()
    private var cache: [String: Data] = [:]
    func data(path: String, page: Int = 1, refresh: Bool = false) async throws -> Data {
        let key = path.replacingOccurrences(of: "/", with: "-") + "-\(page)"
        if ProcessInfo.processInfo.environment["M2_FIXTURES"] == "1", let url = Bundle.main.url(forResource: key, withExtension: "json") { return try Data(contentsOf: url) }
        if !refresh, let data = cache[key] { return data }
        var c = URLComponents(string: "https://api.mangabaka.org/\(path)")!
        if path.split(separator: "/").count > 3 { c.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: "30")] }
        var request = URLRequest(url: c.url!); request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(status) else { throw DetailError.http(status) }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw URLError(.cannotParseResponse) }
        if cache.count >= 100 { cache.removeAll() }; cache[key] = data
        return data
    }
}
enum DetailError: Error { case http(Int) }
@MainActor @Observable final class DetailList {
    var rows: [DetailRecord] = []
    var loading = false
    var failed = false
    var loaded = false
    var hasNext = false
    private var page = 1
    let path: String
    init(path: String) { self.path = path }
    func load(refresh: Bool = false) async {
        guard !loading else { return }; loading = true; failed = false
        defer { loading = false }
        let requestedPage = refresh ? 1 : page
        do {
            let data = try await DetailAPI.shared.data(path: path, page: requestedPage, refresh: refresh)
            let result = try DetailPage.decode(data)
            rows = DetailPage.unique((refresh ? [] : rows) + result.records)
            page = requestedPage + 1; hasNext = result.hasNext; loaded = true
        } catch { failed = true }
    }
}
@MainActor @Observable final class DetailModel {
    var series: DetailRecord?
    var failure: String?
    var loading = false
    let seriesID: String
    let lists: [DetailTab: DetailList]
    let readers: DetailList
    init(id: String) {
        seriesID = id
        lists = Dictionary(uniqueKeysWithValues: DetailTab.allCases.map { ($0, DetailList(path: "v1/series/\(id)/\($0.resource)")) })
        readers = DetailList(path: "v2/series/\(id)/readers-also-like")
    }
    func load(refresh: Bool = false) async {
        guard !loading else { return }; loading = true; failure = nil; defer { loading = false }
        do {
            let data = try await DetailAPI.shared.data(path: "v1/series/\(seriesID)", refresh: refresh)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let record = root["data"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
            series = DetailRecord(record)
        } catch DetailError.http(404) { failure = "This series is unavailable" }
        catch DetailError.http(429) { failure = "Too many requests. Try again later." }
        catch { failure = "Unable to load this section" }
    }
}
