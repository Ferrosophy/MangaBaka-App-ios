import XCTest
import SwiftData
@testable import MangaBakaNative

private final class TestURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do { let (status, data) = try Self.handler!(request); client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self) }
        catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@MainActor private final class MemoryVault: CredentialVault {
    var value: SessionCredentials?
    init(_ value: SessionCredentials?) { self.value = value }
    func load() -> SessionCredentials? { value }
    func save(_ value: SessionCredentials) { self.value = value }
    func clear() { value = nil }
}
@MainActor final class AccountLibraryTests: XCTestCase {
    private func session(expired: Bool = false) -> (AuthSession, MemoryVault) {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [TestURLProtocol.self]
        let vault = MemoryVault(SessionCredentials(access: "test-access", refresh: "test-refresh", expires: Date().addingTimeInterval(expired ? -30 : 3600), profile: AccountProfile(id: "A", name: "Test", avatar: nil)))
        return (AuthSession(configuration: OAuthConfiguration(clientID: "test-client", redirect: URL(string: "test-app://oauthredirect")), transport: URLSession(configuration: configuration), vault: vault), vault)
    }
    private func row(_ id: Int = 1) -> [String: Any] {
        ["id": "entry-\(id)", "state": "completed", "progress_chapter": 83, "progress_volume": 8, "number_of_rereads": 0, "rating": 65,
         "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-02T00:00:00Z", "Series": ["id": id, "title": "Fire Punch", "total_chapters": 83, "final_volume": 8]]
    }
    private func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func repository(_ auth: AuthSession) throws -> LibraryRepository {
        let container = try ModelContainer(for: LibraryCache.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        // ModelContext retains its container.
        return LibraryRepository(auth: auth, context: ModelContext(container))
    }
    func testConcurrentRefreshUsesOneRequestAndKeepsRefreshToken() async throws {
        let (auth, vault) = session(expired: true)
        let lock = NSLock(); var calls = 0
        TestURLProtocol.handler = { request in
            lock.lock(); calls += 1; lock.unlock()
            return (200, try JSONSerialization.data(withJSONObject: ["access_token": "renewed", "expires_in": 3600]))
        }
        async let a = auth.token(); async let b = auth.token()
        let results = try await [a,b]
        XCTAssertEqual(results, ["renewed", "renewed"]); XCTAssertEqual(calls, 1); XCTAssertEqual(vault.value?.refresh, "test-refresh")
    }
    func testUnauthorizedRetriesOnceThenExpires() async throws {
        let (auth, _) = session()
        var requests = 0
        TestURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/token") { return (200, try JSONSerialization.data(withJSONObject: ["access_token": "renewed", "expires_in": 3600])) }
            requests += 1; return (401, Data())
        }
        do { _ = try await auth.request(path: "my/profile"); XCTFail("Expected expiry") } catch { XCTAssertTrue(auth.needsLogin) }
        XCTAssertEqual(requests, 2)
    }
    func testFailedPagePreservesExistingLibrary() async throws {
        let (auth, _) = session(); let library = try repository(auth)
        let initial = try data(["data": [row()]])
        TestURLProtocol.handler = { _ in (200, initial) }; await library.sync()
        XCTAssertEqual(library.entries.count, 1)
        let page = try data(["data": (1...100).map { row($0) }])
        TestURLProtocol.handler = { r in r.url!.query!.contains("page=1&") ? (200, page) : (500, Data()) }
        await library.sync(); XCTAssertEqual(library.entries.count, 1); XCTAssertNotNil(library.error)
    }
    func testEmptyFullSyncRemovesRemoteDeletedRecords() async throws {
        let (auth, _) = session(); let library = try repository(auth)
        let initial = try data(["data": [row()]])
        TestURLProtocol.handler = { _ in (200, initial) }; await library.sync()
        TestURLProtocol.handler = { _ in (200, Data("{\"data\":[]}".utf8)) }; await library.sync()
        XCTAssertTrue(library.entries.isEmpty); XCTAssertTrue(library.complete)
    }
    func testOfflineWriteIsRejectedWithoutHTTPRequest() async throws {
        let (auth, _) = session(); let library = try repository(auth)
        library.activate(); library.online = false
        TestURLProtocol.handler = { _ in XCTFail("Offline edit must not send a request"); return (500, Data()) }
        do { try await library.save(LibraryEntry.parse(row())); XCTFail("Expected read-only error") } catch {}
    }
    func testLogoutClearsCredentialsAndCachedAccount() async throws {
        let (auth, vault) = session(); let library = try repository(auth)
        let initial = try data(["data": [row()]]); TestURLProtocol.handler = { _ in (200, initial) }
        await library.sync(); try library.clearForLogout()
        XCTAssertNil(vault.value); XCTAssertTrue(library.entries.isEmpty); XCTAssertFalse(auth.isAuthenticated)
    }
    func testInvalidRecordCannotReplaceCache() async throws {
        let (auth, _) = session(); let library = try repository(auth)
        TestURLProtocol.handler = { _ in (200, Data("{\"data\":[{\"id\":1}]}".utf8)) }
        await library.sync(); XCTAssertFalse(library.complete); XCTAssertNotNil(library.error)
    }
    func testStatisticsSeparateCompletionFinishAndUnrated() throws {
        var a = try LibraryEntry.parse(row()); var b = a; b.seriesID = "2"; b.state = .dropped; b.rating = nil
        var c = a; c.seriesID = "3"; c.state = .reading; c.rating = 0; a.rereads = 2
        let s = LibraryStatistics(entries: [a,b,c])
        XCTAssertEqual(s.completion, 100.0/3, accuracy: 0.001); XCTAssertEqual(s.finish, 50); XCTAssertEqual(s.mean, 32.5); XCTAssertEqual(s.rereads, 2)
        XCTAssertEqual(s.chapters, 249); XCTAssertEqual(s.highest?.id, "1")
    }
    func testBackupRoundTripAndDuplicateRejection() throws {
        let entry = try LibraryEntry.parse(row())
        let b = LibraryBackup(version: 1, exportedAt: Date(), accountName: "Test", entries: [entry])
        XCTAssertEqual(try LibraryBackup.decode(JSONEncoder().encode(b)).entries, [entry])
        let duplicate = LibraryBackup(version: 1, exportedAt: Date(), accountName: "Test", entries: [entry, entry])
        XCTAssertThrowsError(try LibraryBackup.decode(JSONEncoder().encode(duplicate)))
    }
    func testUnknownTotalsAndZeroScoreArePreserved() throws {
        var e = try LibraryEntry.parse(row()); e.totalChapters = nil; e.totalVolumes = nil; e.rating = 0
        XCTAssertNil(e.percentage); XCTAssertEqual(LibraryStatistics(entries: [e]).mean, 0)
    }
    func testPKCEVerifierAndConfiguration() throws {
        let a = try AuthSession.random(), b = try AuthSession.random()
        XCTAssertEqual(a.count, 43); XCTAssertNotEqual(a, b); XCTAssertFalse(a.contains("="))
        XCTAssertFalse(OAuthConfiguration(clientID: "", redirect: URL(string: "app://oauthredirect")).valid)
        XCTAssertFalse(OAuthConfiguration(clientID: "client", redirect: URL(string: "https://example.com")).valid)
    }
}
