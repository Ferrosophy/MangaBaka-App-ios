import SwiftUI

extension Preferences {
    static let ratings = ["safe", "suggestive", "erotica", "pornographic"]
    static let ratingNames = ["Safe content", "Suggestive", "Erotica", "Pornographic"]
    func allows(_ rating: String?) -> Bool { rating == nil || rating == "" || visibleRatings.contains(rating!) }
    func title(_ card: HomeCard) -> String {
        let code = titleLanguage == "auto" ? (locale.identifier.hasPrefix("zh") ? "zh" : "en") : titleLanguage
        if code == "native", let native = card.nativeTitle, !native.isEmpty { return native }
        return card.localizedTitles[code] ?? card.localizedTitles["en"] ?? card.title
    }
    func title(_ entry: LibraryEntry) -> String {
        title(HomeCard(id: entry.id, title: entry.title, localizedTitles: entry.localizedTitles, image: entry.coverURL, link: nil, date: nil, volume: "", count: nil, contentRating: entry.contentRating, nativeTitle: entry.nativeTitle))
    }
    func dismissed(_ account: String) -> Set<String> { Set(defaults.stringArray(forKey: "dismissed-" + account) ?? []) }
    func dismissSeries(_ id: String, account: String) { var ids = dismissed(account); ids.insert(id); defaults.set(Array(ids), forKey: "dismissed-" + account) }
    var policyKey: String { visibleRatings.sorted().joined(separator: ",") + "|\(hideLibrary)" }
}
struct ContentRatingKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var coverRating: String? { get { self[ContentRatingKey.self] } set { self[ContentRatingKey.self] = newValue } }
}
struct PolicyCover: View {
    let url: URL?
    let rating: String?
    @Environment(Preferences.self) private var preferences
    var body: some View {
        CoverImage(url: url).environment(\.coverRating, rating)
    }
}
