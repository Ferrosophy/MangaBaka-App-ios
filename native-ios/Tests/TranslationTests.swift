import XCTest
import CryptoKit
@testable import MangaBakaNative

final class TranslationTests: XCTestCase {
    private let credentials = TranslationCredentials(key: "example-key", secret: "example-secret", region: "eastasia")
    func testOfficialRequestsDoNotContainAccountToken() throws {
        for provider in TranslationProvider.allCases {
            let request = try TranslationService.request("Hello", provider: provider, target: "zh-Hans", credentials: credentials, now: Date(timeIntervalSince1970: 0))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
            XCTAssertFalse(request.url!.absoluteString.contains(credentials.key))
            let json = try JSONSerialization.jsonObject(with: request.httpBody!)
            switch provider {
            case .google:
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Api-Key"), credentials.key)
                XCTAssertEqual((json as? [String: String])?["target"], "zh-CN")
            case .bing:
                XCTAssertEqual(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region"), "eastasia")
                XCTAssertEqual((json as? [[String: String]])?.first?["Text"], "Hello")
                XCTAssertTrue(request.url!.absoluteString.contains("to=zh-Hans"))
            case .volcano:
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Date"), "19700101T000000Z")
                XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")!.contains("19700101/cn-north-1/translate/request"))
                XCTAssertEqual((json as? [String: Any])?["TargetLanguage"] as? String, "zh")
            }
        }
    }
    func testVolcanoSignatureAgainstIndependentVector() throws {
        let request = try TranslationService.request("Hello", provider: .volcano, target: "zh-Hans", credentials: credentials, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "HMAC-SHA256 Credential=example-key/19700101/cn-north-1/translate/request, SignedHeaders=content-type;host;x-content-sha256;x-date, Signature=15e36f4ef95e2fe028f6391adb9d0703f34ad9b1233085d84dfb764f0859d4f9")
    }
    func testResponseDecodingAndEntities() throws {
        XCTAssertEqual(try TranslationService.decode(Data(#"{"data":{"translations":[{"translatedText":"Tom &amp; Jerry &#39;猫&#x732b;"}]}}"#.utf8), provider: .google), "Tom & Jerry '猫猫")
        XCTAssertEqual(try TranslationService.decode(Data(#"[{"translations":[{"text":"你好","to":"zh-Hans"}]}]"#.utf8), provider: .bing), "你好")
        XCTAssertEqual(try TranslationService.decode(Data(#"{"TranslationList":[{"Translation":"你好"}]}"#.utf8), provider: .volcano), "你好")
        XCTAssertThrowsError(try TranslationService.decode(Data(#"{"ResponseMetadata":{"Error":{"Code":"Denied"}}}"#.utf8), provider: .volcano))
    }
    func testChunkingRespectsUTF8AndGraphemes() {
        let text = String(repeating: "你好👨‍👩‍👧‍👦。", count: 1000)
        let chunks = TranslationService.chunks(text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 4000 })
        XCTAssertEqual(chunks.joined(), text)
    }
    func testCredentialsRejectHeaderInjection() {
        XCTAssertFalse(TranslationCredentials().valid(for: .google))
        XCTAssertFalse(TranslationCredentials(key: "key\r\nx-test: evil").valid(for: .google))
        XCTAssertFalse(TranslationCredentials(key: "key", region: "region\n").valid(for: .bing))
        XCTAssertFalse(TranslationCredentials(key: "key").valid(for: .volcano))
    }
    @MainActor func testCancelledTranslationCannotReplaceCurrentDescription() async {
        let model = DescriptionTranslationModel(service: SlowTranslation())
        model.start("Old", provider: .google, target: "zh-Hans", credentials: credentials)
        model.clear()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(model.translated); XCTAssertFalse(model.loading); XCTAssertFalse(model.showingTranslation)
    }
    @MainActor func testRefreshDeadlineCancelsAnUnfinishedRead() async {
        let start = Date()
        await RefreshDeadline.run(seconds: 0.03) { try? await Task.sleep(for: .seconds(10)) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
}
private struct SlowTranslation: TextTranslating {
    func translate(_ text: String, provider: TranslationProvider, target: String, credentials: TranslationCredentials) async throws -> String {
        try? await Task.sleep(for: .milliseconds(30)); return "Delayed translation"
    }
}
