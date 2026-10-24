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
    var cover: URL? { ImageCandidates.urls(values["cover"] ?? values["cover_image"]).first }
    var sourceScores: [(name: String, score: Double, url: URL?)] {
        let sources = values["source"] as? [String: [String: Any]] ?? [:]
        return sources.keys.sorted().compactMap { key in
            guard let row = sources[key], let score = Double(HomeCard.string(row["rating_normalized"])), score.isFinite else { return nil }
            return (key, score, Self.sourceURL(key: key, row: row))
        }
    }
    var score: Double? { let scores = sourceScores.map(\.score); return scores.isEmpty ? nil : scores.reduce(0,+) / Double(scores.count) }
    static func sourceURL(key: String, row: [String: Any]) -> URL? {
        if let url = safeURL(row["url"] as? String ?? "") { return url }
        let id = HomeCard.string(row["id"])
        guard !id.isEmpty else { return nil }
        let bases = ["anilist": "https://anilist.co/manga/", "my_anime_list": "https://myanimelist.net/manga/", "kitsu": "https://kitsu.io/manga/", "anime_planet": "https://www.anime-planet.com/manga/", "shikimori": "https://shikimori.one/mangas/", "manga_updates": "https://www.mangaupdates.com/series/", "anime_news_network": "https://www.animenewsnetwork.com/encyclopedia/manga.php?id="]
        return bases[key].flatMap { safeURL($0 + id) }
    }
    static func sourceName(_ key: String) -> String {
        ["anilist": "AniList", "my_anime_list": "MyAnimeList", "kitsu": "Kitsu", "anime_planet": "Anime-Planet", "shikimori": "Shikimori", "manga_updates": "MangaUpdates", "anime_news_network": "Anime News Network"][key] ?? key
    }
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
    nonisolated static func requestURL(path: String, page: Int) -> URL {
        var c = URLComponents(string: "https://api.mangabaka.org/\(path)")!
        if path.hasSuffix("/similar") {
            c.queryItems = [URLQueryItem(name: "limit", value: "20")]
        } else if path.hasSuffix("/readers-also-like") {
            c.queryItems = [URLQueryItem(name: "limit", value: "24")]
        } else if ["/images", "/relationships", "/works", "/collections"].contains(where: path.hasSuffix) {
            c.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: "30")]
        }
        return c.url!
    }
    func data(path: String, page: Int = 1, refresh: Bool = false) async throws -> Data {
        let key = path.replacingOccurrences(of: "/", with: "-") + "-\(page)"
        if ProcessInfo.processInfo.environment["M2_FIXTURES"] == "1", let url = Bundle.main.url(forResource: key, withExtension: "json") { return try Data(contentsOf: url) }
        if !refresh, let data = cache[key] { return data }
        let url = Self.requestURL(path: path, page: page)
        var request = URLRequest(url: url); request.timeoutInterval = 25
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
    var tagPaths: [String: String] = [:]
    let seriesID: String
    let lists: [DetailTab: DetailList]
    let readers: DetailList
    init(id: String) {
        seriesID = id
        lists = Dictionary(uniqueKeysWithValues: DetailTab.allCases.map { ($0, DetailList(path: "v1/series/\(id)/\($0.resource)")) })
        readers = DetailList(path: "v2/series/\(id)/readers-also-like")
    }
    func loadTaxonomy() async {
        guard tagPaths.isEmpty else { return }
        do {
            let data = try await DetailAPI.shared.data(path: "v1/tags")
            let page = try DetailPage.decode(data)
            tagPaths = Dictionary(page.records.map { ($0.text("name").lowercased(), $0.text("name_path")) }, uniquingKeysWith: { first, _ in first })
        } catch { /* Plain tag names remain available if the vocabulary is unavailable. */ }
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

struct ResolvedTagGroup: Identifiable {
    let title: String
    let subgroups: [String: [String]]
    var id: String { title }
    static func resolve(names: [String], paths: [String: String]) -> [ResolvedTagGroup] {
        var groups: [String: [String: Set<String>]] = [:]
        for name in names {
            let path = paths[name.lowercased()].flatMap { $0.isEmpty ? nil : $0 } ?? name
            let parts = path.components(separatedBy: " > ")
            let header = parts.count >= 2 ? parts[0] : "Other"
            let subgroup = parts.count >= 3 ? parts[1] : ""
            let label = parts.count >= 3 ? parts.dropFirst(2).joined(separator: " > ") : (parts.count == 2 ? parts[1] : name)
            groups[header, default: [:]][subgroup, default: []].insert(label)
        }
        return groups.keys.sorted().map { key in ResolvedTagGroup(title: key, subgroups: groups[key]!.mapValues { $0.sorted() }) }
    }
}
