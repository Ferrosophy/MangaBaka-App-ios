import Foundation
import CryptoKit
import Security

enum TranslationProvider: String, CaseIterable, Identifiable, Codable {
    case google, volcano, bing
    var id: String { rawValue }
    var title: String { switch self { case .google: "Google"; case .volcano: "Volcengine"; case .bing: "Bing / Microsoft" } }
}
struct TranslationCredentials: Codable, Equatable {
    var key = ""
    var secret = ""
    var region = ""
    func valid(for provider: TranslationProvider) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ![key, secret, region].contains(where: { $0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) && (provider != .volcano || !secret.isEmpty)
    }
}
struct TranslationVault {
    private func query(_ provider: TranslationProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.ferrosophy.mangabaka.translation", kSecAttrAccount as String: provider.rawValue]
    }
    func load(_ provider: TranslationProvider) throws -> TranslationCredentials {
        var q = query(provider); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return TranslationCredentials() }
        guard status == errSecSuccess, let data = result as? Data else { throw TranslationFailure.storage }
        return try JSONDecoder().decode(TranslationCredentials.self, from: data)
    }
    func save(_ value: TranslationCredentials, for provider: TranslationProvider) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(provider); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw TranslationFailure.storage }
        } else if status != errSecSuccess { throw TranslationFailure.storage }
    }
    func remove(_ provider: TranslationProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TranslationFailure.storage }
    }
}
enum TranslationFailure: LocalizedError {
    case missing, storage, invalidResponse, http(Int)
    var errorDescription: String? {
        switch self {
        case .missing: "Configure this translation service in Settings first."
        case .storage: "Unable to access translation credentials in Keychain."
        case .invalidResponse: "The translation service returned an invalid response."
        case .http(let code): code == 429 ? "Translation limit reached. Try again later." : (code == 401 || code == 403 ? "Translation credentials were rejected. Check your service configuration." : "Translation request failed. Try again later.")
        }
    }
}
protocol TextTranslating {
    func translate(_ text: String, provider: TranslationProvider, target: String, credentials: TranslationCredentials) async throws -> String
}
actor TranslationService: TextTranslating {
    static let shared = TranslationService()
    let session: URLSession
    private var cache: [String: String] = [:]
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 25
            config.httpAdditionalHeaders = ["User-Agent": "MangaBaka-Native/0.4.1"]
            self.session = URLSession(configuration: config, delegate: TranslationRedirectGuard(), delegateQueue: nil)
        }
    }
    func translate(_ text: String, provider: TranslationProvider, target: String, credentials: TranslationCredentials) async throws -> String {
        guard credentials.valid(for: provider) else { throw TranslationFailure.missing }
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let credentialHash = SHA256.hash(data: Data([credentials.key, credentials.secret, credentials.region].joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
        let key = provider.rawValue + "|" + target + "|" + hash + "|" + credentialHash
        if let result = cache[key] { return result }
        var translated: [String] = []
        for chunk in Self.chunks(text) {
            try Task.checkCancellation()
            let request = try Self.request(chunk, provider: provider, target: target, credentials: credentials)
            let (data, response) = try await session.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { throw TranslationFailure.invalidResponse }
            guard (200..<300).contains(status) else { throw TranslationFailure.http(status) }
            translated.append(try Self.decode(data, provider: provider))
        }
        try Task.checkCancellation()
        let result = translated.joined(separator: "\n\n")
        if cache.count >= 100 { cache.removeAll() }; cache[key] = result
        return result
    }
    func checkConnection(provider: TranslationProvider, target: String, credentials: TranslationCredentials) async throws {
        guard credentials.valid(for: provider) else { throw TranslationFailure.missing }
        let request = try Self.request("Hello. This is a connection test.", provider: provider, target: target, credentials: credentials)
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw TranslationFailure.invalidResponse }
        guard (200..<300).contains(status) else { throw TranslationFailure.http(status) }
        _ = try Self.decode(data, provider: provider)
    }
    static func chunks(_ text: String, limit: Int = 4000) -> [String] {
        var result: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") where !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var part = ""
            for character in paragraph {
                if part.utf8.count + String(character).utf8.count > limit, !part.isEmpty { result.append(part); part = "" }
                part.append(character)
            }
            if !part.isEmpty { result.append(part) }
        }
        return result
    }
    static func request(_ text: String, provider: TranslationProvider, target: String, credentials c: TranslationCredentials, now: Date = Date()) throws -> URLRequest {
        let url: URL
        let body: Any
        switch provider {
        case .google:
            url = URL(string: "https://translation.googleapis.com/language/translate/v2")!
            body = ["q": text, "target": target == "zh-Hans" ? "zh-CN" : "en", "format": "text"]
        case .bing:
            url = URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=\(target == "zh-Hans" ? "zh-Hans" : "en")")!
            body = [["Text": text]]
        case .volcano:
            url = URL(string: "https://translate.volcengineapi.com/?Action=TranslateText&Version=2020-06-01")!
            body = ["TextList": [text], "TargetLanguage": target == "zh-Hans" ? "zh" : "en"]
        }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 25
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider {
        case .google: request.setValue(c.key, forHTTPHeaderField: "X-Goog-Api-Key")
        case .bing:
            request.setValue(c.key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            if !c.region.isEmpty { request.setValue(c.region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region") }
        case .volcano: sign(&request, credentials: c, now: now)
        }
        return request
    }
    static func decode(_ data: Data, provider: TranslationProvider) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        var value: String?
        switch provider {
        case .google: value = (((object as? [String: Any])?["data"] as? [String: Any])?["translations"] as? [[String: Any]])?.first?["translatedText"] as? String
        case .bing: value = (((object as? [[String: Any]])?.first?["translations"]) as? [[String: Any]])?.first?["text"] as? String
        case .volcano: value = ((object as? [String: Any])?["TranslationList"] as? [[String: Any]])?.first?["Translation"] as? String
        }
        guard let value, !value.isEmpty else { throw TranslationFailure.invalidResponse }
        return provider == .google ? unescape(value) : value
    }
    static func unescape(_ text: String) -> String {
        var result = text
        let regex = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result), let numberRange = Range(match.range(at: 1), in: result) else { continue }
            let raw = String(result[numberRange]); let n = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let n, let scalar = UnicodeScalar(n) { result.replaceSubrange(range, with: String(scalar)) }
        }
        for (entity, value) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] { result = result.replacingOccurrences(of: entity, with: value) }
        return result
    }
    static func sign(_ request: inout URLRequest, credentials c: TranslationCredentials, now: Date) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let date = f.string(from: now), day = String(date.prefix(8))
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        func hmac(_ data: String, key: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: key))) }
        let bodyHash = hash(request.httpBody ?? Data())
        let headers = "content-type:application/json\nhost:translate.volcengineapi.com\nx-content-sha256:\(bodyHash)\nx-date:\(date)\n"
        let signedHeaders = "content-type;host;x-content-sha256;x-date"
        let canonical = "POST\n/\nAction=TranslateText&Version=2020-06-01\n\(headers)\n\(signedHeaders)\n\(bodyHash)"
        let scope = "\(day)/cn-north-1/translate/request"
        let stringToSign = "HMAC-SHA256\n\(date)\n\(scope)\n\(hash(Data(canonical.utf8)))"
        let signingKey = hmac("request", key: hmac("translate", key: hmac("cn-north-1", key: hmac(day, key: Data(c.secret.utf8)))))
        let signature = hmac(stringToSign, key: signingKey).map { String(format: "%02x", $0) }.joined()
        request.setValue(date, forHTTPHeaderField: "X-Date"); request.setValue(bodyHash, forHTTPHeaderField: "X-Content-Sha256")
        request.setValue("HMAC-SHA256 Credential=\(c.key)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)", forHTTPHeaderField: "Authorization")
    }
}
private final class TranslationRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
