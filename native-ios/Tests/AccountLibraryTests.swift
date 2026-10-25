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
    var failSave = false
    init(_ value: SessionCredentials?) { self.value = value }
    func load() -> SessionCredentials? { value }
    func save(_ value: SessionCredentials) throws { if failSave { throw AccountError.message("Unable to save your session securely.") }; self.value = value }
    func clear() { value = nil }
}
@MainActor final class AccountLibraryTests: XCTestCase {
    private func session() -> (AuthSession, MemoryVault) {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [TestURLProtocol.self]
        let vault = MemoryVault(SessionCredentials(access: "mb-test-access", profile: AccountProfile(id: "A", name: "Test", avatar: nil)))
        return (AuthSession(transport: URLSession(configuration: configuration), vault: vault), vault)
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
    func testPATSignInValidatesProfileBeforeSecurePersistence() async throws {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [TestURLProtocol.self]
        let vault = MemoryVault(nil), response = try data(["data": ["id": "A", "preferred_username": "Test", "auth_type": "pat"]])
        let auth = AuthSession(transport: URLSession(configuration: c), vault: vault)
        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/my/profile")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "mb-example-pat")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, response)
        }
        try await auth.signIn(personalAccessToken: "  mb-example-pat\n")
        XCTAssertTrue(auth.isAuthenticated); XCTAssertEqual(vault.value?.access, "mb-example-pat"); XCTAssertEqual(auth.profile?.id, "A")
    }
    func testUnauthorizedPATExpiresWithoutRefreshOrRetry() async throws {
        let (auth, vault) = session(); var requests = 0
        TestURLProtocol.handler = { request in
            XCTAssertFalse(request.url!.path.contains("oauth")); XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "mb-test-access")
            requests += 1; return (401, Data())
        }
        do { _ = try await auth.request(path: "my/profile"); XCTFail("Expected expiry") } catch { XCTAssertTrue(auth.needsLogin) }
        XCTAssertEqual(requests, 1); XCTAssertNil(vault.value); XCTAssertFalse(auth.isAuthenticated)
    }
    func testNetworkAndPermissionErrorsKeepSavedToken() async throws {
        let (auth, vault) = session()
        TestURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await auth.request(path: "my/profile"); XCTFail("Expected network error") } catch {}
        XCTAssertTrue(auth.isAuthenticated); XCTAssertNotNil(vault.value)
        TestURLProtocol.handler = { _ in (403, Data()) }
        do { _ = try await auth.request(path: "my/profile"); XCTFail("Expected permission error") } catch {}
        XCTAssertTrue(auth.isAuthenticated); XCTAssertNotNil(vault.value)
    }
    func testFailedCredentialSaveDoesNotAuthenticate() async throws {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [TestURLProtocol.self]
        let vault = MemoryVault(nil); vault.failSave = true
        let auth = AuthSession(transport: URLSession(configuration: c), vault: vault)
        let response = try data(["data": ["id": "A", "auth_type": "pat"]])
        TestURLProtocol.handler = { _ in (200, response) }
        do { try await auth.signIn(personalAccessToken: "mb-example-pat"); XCTFail("Expected storage error") } catch {}
        XCTAssertFalse(auth.isAuthenticated); XCTAssertNil(vault.value)
    }
    func testInvalidProfileNeverSavesToken() async throws {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [TestURLProtocol.self]
        let vault = MemoryVault(nil)
        let auth = AuthSession(transport: URLSession(configuration: c), vault: vault)
        TestURLProtocol.handler = { _ in (200, Data("{\"data\":{}}".utf8)) }
        do { try await auth.signIn(personalAccessToken: "mb-example-pat"); XCTFail("Expected profile error") } catch {}
        XCTAssertFalse(auth.isAuthenticated); XCTAssertNil(vault.value)
    }
    func testLogoutInvalidatesInFlightResponse() async throws {
        let (auth, _) = session(); let started = expectation(description: "request started"), gate = DispatchSemaphore(value: 0)
        TestURLProtocol.handler = { _ in started.fulfill(); _ = gate.wait(timeout: .now()+5); return (200, Data("{}".utf8)) }
        let request = Task { try await auth.request(path: "my/profile") }
        await fulfillment(of: [started], timeout: 3)
        try auth.logout(); gate.signal()
        do { _ = try await request.value; XCTFail("Old account response must be rejected") } catch AccountError.stale {} catch { XCTFail("Expected stale-account error") }
        XCTAssertFalse(auth.isAuthenticated)
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
        XCTAssertEqual(s.completion, 100.0/3, accuracy: 0.001); XCTAssertEqual(s.finish, 50); XCTAssertEqual(s.mean, 65); XCTAssertEqual(s.rereads, 2)
        XCTAssertEqual(s.chapters, 249); XCTAssertEqual(s.highest?.id, "1")
    }
    func testBackupRoundTripAndDuplicateRejection() throws {
        let entry = try LibraryEntry.parse(row())
        let b = LibraryBackup(version: 1, exportedAt: Date(), accountName: "Test", entries: [entry])
        XCTAssertEqual(try LibraryBackup.decode(JSONEncoder().encode(b)).entries, [entry])
        let duplicate = LibraryBackup(version: 1, exportedAt: Date(), accountName: "Test", entries: [entry, entry])
        XCTAssertThrowsError(try LibraryBackup.decode(JSONEncoder().encode(duplicate)))
    }
    func testUnknownTotalsAndZeroScoreIsUnrated() throws {
        var e = try LibraryEntry.parse(row()); e.totalChapters = nil; e.totalVolumes = nil; e.rating = 0
        XCTAssertNil(e.percentage); XCTAssertNil(LibraryStatistics(entries: [e]).mean)
    }
    func testPartialUpdateDoesNotOverwriteOtherFields() throws {
        let before = try LibraryEntry.parse(row()); var after = before
        after.chapters = 82
        let fields = LibraryRepository.changedFields(after, previous: before)
        XCTAssertEqual(fields.count, 1); XCTAssertEqual(fields["progress_chapter"] as? Double, 82)
        XCTAssertNil(fields["rating"]); XCTAssertNil(fields["state"])
    }
    func testClearScoreSendsExplicitNull() throws {
        let before = try LibraryEntry.parse(row()); var after = before; after.rating = nil
        XCTAssertTrue(LibraryRepository.changedFields(after, previous: before)["rating"] is NSNull)
    }
    func testPATFormatRejectsHeaderInjectionAndOAuthTokens() throws {
        XCTAssertTrue(AuthSession.validPAT("mb-example-token"))
        for invalid in ["", "mb-", "Bearer example", "mb-token\nInjected: header", "mb-token with spaces", "mb-é", String(repeating: "x", count: 5000)] { XCTAssertFalse(AuthSession.validPAT(invalid)) }
    }
    func testV2LibraryEnvelopePreservesFractionalProgressAndUnknownDates() throws {
        var flat = row(); let series = flat.removeValue(forKey: "Series")!
        flat.removeValue(forKey: "created_at"); flat.removeValue(forKey: "updated_at")
        flat["progress_chapter"] = 12.5; flat["rating"] = 0
        let e = try LibraryEntry.parse(["entry": flat, "series": series, "lists": []])
        XCTAssertEqual(e.chapters, 12.5); XCTAssertNil(e.createdAt); XCTAssertNil(e.updatedAt); XCTAssertNil(e.rating)
    }
    func testAPIProgressAndRereadLimits() throws {
        var e = try LibraryEntry.parse(row()); e.chapters = 10001; XCTAssertThrowsError(try e.validateBackup())
        e.chapters = 10000; e.rereads = 1001; XCTAssertThrowsError(try e.validateBackup())
        e.rereads = 1000; XCTAssertNoThrow(try e.validateBackup())
    }
    func testBackupDoesNotContainPAT() throws {
        let b = LibraryBackup(version: 1, exportedAt: Date(), accountName: "Test", entries: [try LibraryEntry.parse(row())])
        let text = String(data: try JSONEncoder().encode(b), encoding: .utf8)!
        XCTAssertFalse(text.contains("mb-test-access")); XCTAssertFalse(text.contains("x-api-key"))
    }
}
