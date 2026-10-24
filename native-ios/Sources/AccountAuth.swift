import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit
import Observation

enum AccountError: LocalizedError {
    case message(String), http(Int), expired, stale
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .http(let code): return code == 429 ? "Too many requests. Try again later." : code == 403 ? "This account does not have permission for this action." : "The server rejected the request. Please try again."
        case .expired: return "Your session has expired. Sign in again."
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
    var refresh: String?
    var expires: Date?
    var profile: AccountProfile?
}
struct OAuthConfiguration {
    let clientID: String
    let redirect: URL?
    static var bundled: Self {
        Self(clientID: Bundle.main.object(forInfoDictionaryKey: "MangaBakaClientID") as? String ?? "", redirect: URL(string: Bundle.main.object(forInfoDictionaryKey: "MangaBakaRedirectURI") as? String ?? ""))
    }
    var valid: Bool { !clientID.isEmpty && !clientID.contains("$(") && redirect?.scheme != nil && redirect?.scheme != "https" && redirect?.scheme != "http" }
}
enum SessionKeychain {
    static let service = "dev.ferrosophy.mangabaka.native.oauth"
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
@MainActor @Observable final class AuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    var profile: AccountProfile?
    var signingIn = false
    var needsLogin = false
    var error: String?
    var storageWarning: String?
    private(set) var generation = UUID()
    private var credentials: SessionCredentials?
    private var browser: ASWebAuthenticationSession?
    private var refreshTask: Task<String, Error>?
    let configuration: OAuthConfiguration
    let transport: URLSession
    private let vault: any CredentialVault
    var isAuthenticated: Bool { credentials != nil && profile != nil && !needsLogin }
    init(configuration: OAuthConfiguration = .bundled, transport: URLSession = .shared, vault: (any CredentialVault)? = nil) {
        self.configuration = configuration; self.transport = transport; self.vault = vault ?? KeychainVault()
        super.init()
        do { credentials = try self.vault.load(); profile = credentials?.profile }
        catch { self.storageWarning = "Unable to access secure account storage." }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AccountError.message("Unable to start secure sign-in.") }
        return base64(Data(bytes))
    }
    static func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    func login() async {
        guard !signingIn else { return }
        guard configuration.valid, let redirect = configuration.redirect else { error = "OAuth client configuration is missing. Configure a registered Client ID and redirect URI."; return }
        signingIn = true; error = nil
        defer { signingIn = false; browser = nil }
        let epoch = generation
        do {
            let verifier = try Self.random(), state = try Self.random()
            var c = URLComponents(string: "https://mangabaka.org/auth/oauth2/authorize")!
            c.queryItems = ["client_id": configuration.clientID, "redirect_uri": redirect.absoluteString, "response_type": "code", "scope": "openid profile offline_access", "state": state, "code_challenge": Self.base64(Data(SHA256.hash(data: Data(verifier.utf8)))), "code_challenge_method": "S256", "prompt": "consent"].map { URLQueryItem(name: $0.key, value: $0.value) }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: redirect.scheme) { url, error in
                    if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? CancellationError()) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                browser = session
                if !session.start() { continuation.resume(throwing: AccountError.message("Unable to open the sign-in page.")) }
            }
            guard generation == epoch else { throw AccountError.stale }
            let q = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard callback.scheme == redirect.scheme, callback.host == redirect.host, callback.path == redirect.path,
                  q.filter({ $0.name == "state" }).count == 1, q.first(where: { $0.name == "state" })?.value == state,
                  let code = q.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw AccountError.message("Sign-in callback was rejected. Try signing in again.") }
            var next = try await exchange(["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": redirect.absoluteString])
            let me = try await loadProfile(token: next.access)
            guard generation == epoch else { throw AccountError.stale }
            next.profile = me
            try vault.save(next)
            credentials = next; profile = me; needsLogin = false; generation = UUID()
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin { }
        catch is CancellationError { }
        catch { self.error = (error as? AccountError)?.errorDescription ?? "Sign-in failed. Check your connection and try again." }
    }
    private func exchange(_ fields: [String: String], previous: SessionCredentials? = nil) async throws -> SessionCredentials {
        var fields = fields; fields["client_id"] = configuration.clientID
        var c = URLComponents(); c.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://mangabaka.org/auth/oauth2/token")!); request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // URL query encoding permits '+', which form decoders interpret as spaces.
        request.httpBody = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await transport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if d["error"] as? String == "invalid_grant" { throw AccountError.expired }
        guard (200..<300).contains(status), let access = d["access_token"] as? String, !access.isEmpty else { throw AccountError.http(status) }
        return SessionCredentials(access: access, refresh: d["refresh_token"] as? String ?? previous?.refresh, expires: (d["expires_in"] as? NSNumber).map { Date().addingTimeInterval($0.doubleValue) }, profile: previous?.profile)
    }
    func token(rejected: String? = nil) async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let current = credentials, !needsLogin else { throw AccountError.expired }
        if let rejected, current.access != rejected { return current.access }
        if rejected == nil, current.expires.map({ $0.timeIntervalSinceNow > 300 }) ?? true { return current.access }
        guard let refresh = current.refresh else { expire(); throw AccountError.expired }
        let epoch = generation
        let task = Task { @MainActor in
            do {
                let next = try await exchange(["grant_type": "refresh_token", "refresh_token": refresh], previous: current)
                guard epoch == generation else { throw AccountError.stale }
                try vault.save(next); credentials = next
                return next.access
            } catch AccountError.expired { if epoch == generation { expire() }; throw AccountError.expired }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    func request(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        let epoch = generation
        var access = try await token()
        for attempt in 0...1 {
            guard generation == epoch else { throw AccountError.stale }
            var request = URLRequest(url: URL(string: "https://api.mangabaka.org/v1/" + path)!); request.httpMethod = method; request.timeoutInterval = 25
            request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization"); request.setValue("MangaBaka-Native/0.3.0", forHTTPHeaderField: "User-Agent")
            if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
            let (data, response) = try await transport.data(for: request)
            guard generation == epoch else { throw AccountError.stale }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                if attempt == 0 { access = try await token(rejected: access); continue }
                expire(); throw AccountError.expired
            }
            if method == "DELETE", status == 404 { return Data() }
            guard (200..<300).contains(status) else { throw AccountError.http(status) }
            return data
        }
        throw AccountError.expired
    }
    private func loadProfile(token: String) async throws -> AccountProfile {
        for url in ["https://api.mangabaka.org/v1/my/profile", "https://mangabaka.org/auth/oauth2/userinfo"] {
            var r = URLRequest(url: URL(string: url)!); r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); r.timeoutInterval = 25
            let (d, response) = try await transport.data(for: r)
            if (response as? HTTPURLResponse)?.statusCode == 200, let object = try JSONSerialization.jsonObject(with: d) as? [String: Any], let p = try? AccountProfile.parse(object) { return p }
        }
        throw AccountError.message("Unable to confirm your account. Try signing in again.")
    }
    func expire() { credentials = nil; needsLogin = true; generation = UUID(); try? vault.clear() }
    func logout() throws {
        browser?.cancel(); generation = UUID(); refreshTask?.cancel(); refreshTask = nil
        try vault.clear(); credentials = nil; profile = nil; needsLogin = false; error = nil
    }
}
