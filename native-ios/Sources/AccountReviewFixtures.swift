#if DEBUG && targetEnvironment(simulator)
import Foundation

// Synthetic data for simulator review only. Absent from Release/IPAs.
@MainActor enum AccountReviewFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.environment["M3_ACCOUNT_FIXTURES"] == "1" }
    static func session() -> AuthSession {
        ReviewAPIProtocol.configureLayout()
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [ReviewAPIProtocol.self]
        return AuthSession(transport: URLSession(configuration: c), vault: ReviewVault())
    }
}
@MainActor private final class ReviewVault: CredentialVault {
    var value: SessionCredentials?
    func load() throws -> SessionCredentials? { value }
    func save(_ value: SessionCredentials) throws { self.value = value }
    func clear() throws { value = nil }
}
private final class ReviewAPIProtocol: URLProtocol {
    static let lock = NSLock()
    static var entries: [[String: Any]] = [
        ["id": 1, "series_id": 1677, "user_id": "review", "state": "completed", "progress_chapter": 232, "progress_volume": 24, "rating": 65, "number_of_rereads": 0, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-03T00:00:00Z"],
        ["id": 2, "series_id": 2, "user_id": "review", "state": "reading", "progress_chapter": 10, "progress_volume": 1, "rating": NSNull(), "number_of_rereads": 0, "created_at": "2026-01-02T00:00:00Z", "updated_at": "2026-01-04T00:00:00Z"]
    ]
    static func configureLayout() {
        guard ProcessInfo.processInfo.environment["M4_LAYOUT_REVIEW"] == "1" else { return }
        lock.lock(); defer { lock.unlock() }
        entries = (101...106).map { id in ["id": id, "series_id": id, "state": "reading", "progress_chapter": id - 100, "progress_volume": 0, "rating": NSNull(), "number_of_rereads": 0, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"] }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.mangabaka.org" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let path = request.url!.path
        var status = 200
        var body: [String: Any] = ["status": 200, "data": true]
        if request.value(forHTTPHeaderField: "x-api-key") != "mb-simulator-review" { status = 401; body = ["status": 401] }
        else if path.hasSuffix("/my/profile") {
            body = ["status": 200, "data": ["id": "review", "preferred_username": "Simulator Review", "auth_type": "pat", "scopes": ["library.read", "library.write"]]]
        } else if path == "/v2/my/library" {
            body = ["status": 200, "pagination": ["count": Self.entries.count, "page": 1, "limit": 100, "next": NSNull(), "previous": NSNull()], "data": Self.entries.map { entry -> [String: Any] in
                let id = entry["series_id"] as! Int
                var series: [String: Any] = ["id": id, "title": "Review Series", "total_chapters": 83, "final_volume": 8]
                if id == 1677, let url = Bundle.main.url(forResource: "v1-series-1677-1", withExtension: "json"), let d = try? Data(contentsOf: url), let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let actual = root["data"] as? [String: Any] { series = actual }
                if ProcessInfo.processInfo.environment["M4_LAYOUT_REVIEW"] == "1" {
                    let shapes = ["portrait", "landscape", "square"]
                    series = ["id": id, "title": id % 2 == 0 ? "A very long library title spanning two lines" : "Short", "content_rating": "safe", "cover": "https://layout-review.invalid/" + shapes[(id - 101) % 3], "total_chapters": id == 103 ? NSNull() : 20, "final_volume": NSNull()]
                }
                return ["entry": entry, "series": series, "lists": []]
            }]
        } else if path.contains("/my/library/"), let id = Int(path.split(separator: "/").last ?? "") {
            if request.httpMethod == "DELETE" { Self.entries.removeAll { $0["series_id"] as? Int == id } }
            else if let index = Self.entries.firstIndex(where: { $0["series_id"] as? Int == id }), let data = readBody(), let changes = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.entries[index].merge(changes) { _, new in new }
            } else { status = 404 }
        } else { status = 404 }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    private func readBody() -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; result.append(buffer, count: n) }
        return result
    }
    override func stopLoading() {}
}
#endif
