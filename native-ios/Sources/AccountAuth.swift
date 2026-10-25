import Foundation
import Security
import Observation

enum AccountError: LocalizedError {
    case message(String), http(Int), expired, stale
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .http(let code): return code == 429 ? "Too many requests. Try again later." : code == 403 ? "This account does not have permission for this action." : "The server rejected the request. Please try again."
        case .expired: return "Your personal access token is invalid or revoked. Create a new token and sign in again."
        case .stale: return "The account has changed. Please try again."
        }
    }
}
struct AccountProfile: Codable, Equatable {
    let id: String
    let name: String
    let avatar: URL?
    static func parse(_ object: [String: Any]) throws -> Self {
        let d = object["data"] as? [String: Any] ?? object
        let id = HomeCard.string(d["id"] ?? d["sub"])
        guard !id.isEmpty else { throw AccountError.message("The server did not return an account ID.") }
        return Self(id: id, name: HomeCard.string(d["preferred_username"] ?? d["nickname"] ?? d["name"] ?? d["username"] ?? d["handle"] ?? id), avatar: ["avatar", "avatar_url", "picture", "image", "profile_picture"].compactMap { Self.avatarURL(d[$0]) }.first)
    }
    static func avatarURL(_ value: Any?) -> URL? {
        if let raw = value as? String, !raw.isEmpty {
            guard let url = URL(string: raw, relativeTo: URL(string: "https://mangabaka.org"))?.absoluteURL else { return nil }
            return safeURL(url.absoluteString)
        }
        if let map = value as? [String: Any] {
            for key in ["url", "x250", "raw", "x1", "image", "original"] { if let url = avatarURL(map[key]) { return url } }
        }
        return nil
    }

}
struct SessionCredentials: Codable {
    var access: String
    var profile: AccountProfile?
}
enum SessionKeychain {
    static let service = "dev.ferrosophy.mangabaka.native.pat"
    static func query() -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"] }
    static func load() throws -> SessionCredentials? {
        var q = query(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AccountError.message("Unable to access secure account storage.") }
        return try JSONDecoder().decode(SessionCredentials.self, from: data)
    }
    static func save(_ value: SessionCredentials) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(); q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw AccountError.message("Unable to save your session securely.") }; return
        }
        guard status == errSecSuccess else { throw AccountError.message("Unable to save your session securely.") }
    }
    static func clear() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.message("Unable to remove the saved session.") }
    }
}
@MainActor protocol CredentialVault {
    func load() throws -> SessionCredentials?
    func save(_ value: SessionCredentials) throws
    func clear() throws
}
struct KeychainVault: CredentialVault {
    func load() throws -> SessionCredentials? { try SessionKeychain.load() }
    func save(_ value: SessionCredentials) throws { try SessionKeychain.save(value) }
    func clear() throws { try SessionKeychain.clear() }
}
// Never forward a PAT to another host through an HTTP redirect.
final class AccountRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        completionHandler(url?.scheme == "https" && url?.host == "api.mangabaka.org" && (url?.port == nil || url?.port == 443) ? request : nil)
    }
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: AccountRedirectDelegate(), delegateQueue: nil)
    }
}
@MainActor @Observable final class AuthSession {
    var profile: AccountProfile?
    var signingIn = false
    var showingSignIn = false
    var needsLogin = false
    var error: String?
    var storageWarning: String?
    private(set) var generation = UUID()
    private var credentials: SessionCredentials?
    let transport: URLSession
    private let vault: any CredentialVault
    var isAuthenticated: Bool { credentials != nil && profile != nil && !needsLogin }
    init(transport: URLSession? = nil, vault: (any CredentialVault)? = nil) {
        self.transport = transport ?? AccountRedirectDelegate.makeSession(); self.vault = vault ?? KeychainVault()
        do {
            if let saved = try self.vault.load() {
                guard Self.validPAT(saved.access), saved.profile != nil else { try self.vault.clear(); return }
                credentials = saved; profile = saved.profile
            }
        } catch { storageWarning = "Unable to access secure account storage." }
    }
    static func validPAT(_ raw: String) -> Bool {
        raw.hasPrefix("mb-") && raw.count > 3 && raw.utf8.count <= 4096 && raw.unicodeScalars.allSatisfy { (33...126).contains(Int($0.value)) }
    }
    func login() async { showingSignIn = true }
    func signIn(personalAccessToken raw: String) async throws {
        guard !signingIn else { return }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validPAT(token) else { throw AccountError.message("Enter a valid personal access token starting with mb-.") }
        signingIn = true; defer { signingIn = false }
        let epoch = generation
        let data = try await send(path: "my/profile", version: 1, method: "GET", body: nil, token: token)
        guard generation == epoch else { throw AccountError.stale }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AccountError.message("Unable to confirm your account. Check your token and try again.") }
        let details = object["data"] as? [String: Any] ?? object
        if let kind = details["auth_type"] as? String, kind != "pat" { throw AccountError.message("Enter a personal access token, not an OAuth access token.") }
        let me = try AccountProfile.parse(object)
        let next = SessionCredentials(access: token, profile: me)
        try vault.save(next)
        credentials = next; profile = me; needsLogin = false; storageWarning = nil; error = nil; generation = UUID()
    }
    func request(path: String, version: Int = 1, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let current = credentials, !needsLogin else { throw AccountError.expired }
        let epoch = generation
        do {
            let data = try await send(path: path, version: version, method: method, body: body, token: current.access)
            guard generation == epoch else { throw AccountError.stale }
            return data
        } catch {
            guard generation == epoch else { throw AccountError.stale }
            if case AccountError.expired = error { expire() }
            throw error
        }
    }
    private func send(path: String, version: Int, method: String, body: [String: Any]?, token: String) async throws -> Data {
        guard [1,2].contains(version), let url = URL(string: "https://api.mangabaka.org/v\(version)/" + path), url.host == "api.mangabaka.org" else { throw AccountError.stale }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "x-api-key")
        request.setValue("MangaBaka-Native/0.3.0", forHTTPHeaderField: "User-Agent")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await transport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AccountError.expired }
        if method == "DELETE", status == 404 { return Data() }
        guard (200..<300).contains(status) else { throw AccountError.http(status) }
        return data
    }
    func expire() {
        credentials = nil; needsLogin = true; generation = UUID()
        error = AccountError.expired.errorDescription
        do { try vault.clear() } catch { storageWarning = "Unable to remove the saved session." }
    }
    func logout() throws {
        try vault.clear()
        generation = UUID(); credentials = nil; profile = nil; needsLogin = false; error = nil; storageWarning = nil; showingSignIn = false
    }
}
