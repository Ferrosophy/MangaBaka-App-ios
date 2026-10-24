import Foundation
import Observation

enum Shelf: String, CaseIterable, Identifiable {
    case trending, upcoming, publishers, rising, gems, recent
    var id: String { rawValue }
    var title: String {
        switch self { case .trending: "Trending"; case .upcoming: "Upcoming Releases"; case .publishers: "Popular Publishers"; case .rising: "Rising"; case .gems: "Hidden Gems"; case .recent: "New Releases" }
    }
}
struct HomeCard: Identifiable {
    let id: String
    let title: String
    let localizedTitles: [String: String]
    let image: URL?
    let link: URL?
    let date: Date?
    let volume: String
    let count: Int?
    var seriesID: String? = nil
    func displayTitle(locale: Locale) -> String {
        let key = locale.identifier.hasPrefix("zh") ? "zh" : "en"
        return localizedTitles[key] ?? title
    }
    static func string(_ value: Any?) -> String { value.map { String(describing: $0) } ?? "" }
    static func imageURL(_ raw: Any?) -> URL? {
        if let s = raw as? String { return URL(string: s) }
        guard let map = raw as? [String: Any] else { return nil }
        for key in ["x350", "x250", "x150", "raw", "url", "x1"] {
            if let url = imageURL(map[key]) { return url }
        }
        return nil
    }
    static func parse(_ json: [String: Any], shelf: Shelf) -> HomeCard? {
        let id = string(json["id"])
        guard !id.isEmpty else { return nil }
        var titles: [String: String] = [:]
        for t in json["titles"] as? [[String: Any]] ?? [] {
            let language = string(t["language"])
            let title = string(t["title"])
            if !title.isEmpty, language == "en" || language == "zh" || language == "zh-Hans" || language == "zh-CN" {
                titles[language.hasPrefix("zh") ? "zh" : "en"] = title
            }
        }
        let firstTitle = (json["titles"] as? [[String: Any]])?.first?["title"] as? String
        var title = titles["en"] ?? json["title"] as? String ?? firstTitle ?? ""
        var image = imageURL(json["cover"] ?? json["cover_image"])
        var link = URL(string: "https://mangabaka.org/" + id)
        var date: Date?
        var volume = ""
        var count: Int?
        if shelf == .publishers {
            title = string(json["name"])
            image = imageURL(json["logo"])
            if let url = image, url.pathExtension.lowercased() == "svg" {
                let encoded = Data(url.absoluteString.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                image = URL(string: "https://cdn.mangabaka.dev/imgproxy/plain/x150@2/\(encoded).webp")
            }
            count = Int(string(json["series_count"]))
            link = URL(string: json["canonical_url"] as? String ?? "https://mangabaka.org/publishers/\(id)")
        } else if shelf == .upcoming {
            title = (json["collections"] as? [[String: Any]])?.first?["title"] as? String ?? string(json["sub_title"])
            image = imageURL((json["images"] as? [[String: Any]])?.first?["image"])
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.date(from: String(string(json["release_date"]).prefix(10)))
            volume = string(json["sequence_string"])
            let seriesID = string(json["series_id"])
            link = seriesID.isEmpty ? nil : URL(string: "https://mangabaka.org/\(seriesID)")
        }
        guard !title.isEmpty else { return nil }
        return HomeCard(id: id, title: title, localizedTitles: titles, image: image, link: link, date: date, volume: volume, count: count, seriesID: shelf == .publishers ? nil : (shelf == .upcoming ? (string(json["series_id"]).isEmpty ? nil : string(json["series_id"])) : id))
    }
}
protocol HomeProviding {
    func load(_ shelf: Shelf, type: String, days: Int) async throws -> [HomeCard]
}
struct HomeService: HomeProviding {
    static func requestURL(_ shelf: Shelf, type: String, days: Int, now: Date = Date()) -> URL {
        var path = "/v2/series/search"
        var query = [URLQueryItem(name: "limit", value: "20")]
        switch shelf {
        case .trending:
            query.append(URLQueryItem(name: "sort_by", value: days == 30 ? "trending_30d" : "trending_7d"))
            if !type.isEmpty { query.append(URLQueryItem(name: "type", value: type)) }
        case .upcoming: path = "/v1/works/upcoming"; query = [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "per_page", value: "25")]
        case .publishers: path = "/v2/publishers"; query = [URLQueryItem(name: "sort_by", value: "series_count_desc"), URLQueryItem(name: "limit", value: "16")]
        case .rising: path = "/v2/series/discover/rising"; query.append(URLQueryItem(name: "window_days", value: "7"))
        case .gems: path = "/v2/series/discover/hidden-gems"
        case .recent:
            let date = now.addingTimeInterval(-365 * 86400)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; f.timeZone = TimeZone(secondsFromGMT: 0)
            query += [URLQueryItem(name: "sort_by", value: "published_start_date_desc"), URLQueryItem(name: "published_start_date_lower", value: f.string(from: date)), URLQueryItem(name: "rating_lower", value: "1")]
        }
        var components = URLComponents(); components.scheme = "https"; components.host = "api.mangabaka.org"; components.path = path; components.queryItems = query
        return components.url!
    }
    func load(_ shelf: Shelf, type: String, days: Int) async throws -> [HomeCard] {
        var request = URLRequest(url: Self.requestURL(shelf, type: type, days: days)); request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        let object = try JSONSerialization.jsonObject(with: data)
        let map = object as? [String: Any]
        guard let rows = (map?["data"] ?? map?["results"] ?? object) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var seen = Set<String>()
        return rows.compactMap { HomeCard.parse($0, shelf: shelf) }.filter { seen.insert($0.id).inserted }
    }
}
@MainActor @Observable final class HomeModel {
    struct State { var cards: [HomeCard] = []; var loading = true; var failed = false }
    var states: [Shelf: State] = [:]
    var type = ""
    var days = 7
    private var generations: [Shelf: UUID] = [:]
    private let service: any HomeProviding
    init(service: any HomeProviding = HomeService()) { self.service = service }
    func load(_ shelf: Shelf) async {
        let token = UUID(); generations[shelf] = token
        var state = states[shelf] ?? State(); state.loading = true; state.failed = false; states[shelf] = state
        do {
            let cards = try await service.load(shelf, type: type, days: days)
            guard generations[shelf] == token else { return }
            states[shelf] = State(cards: cards, loading: false, failed: false)
        } catch {
            guard generations[shelf] == token else { return }
            state.loading = false; state.failed = true; states[shelf] = state
        }
    }
    func refresh() async { await withTaskGroup(of: Void.self) { group in for shelf in Shelf.allCases { group.addTask { await self.load(shelf) } } } }
}
