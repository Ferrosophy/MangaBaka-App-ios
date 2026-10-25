import SwiftUI

struct GeneralSettingsView: View {
    @Environment(Preferences.self) private var preferences
    var body: some View {
        @Bindable var p = preferences
        Form {
            Picker("Language", selection: $p.language) { Text("Follow System").tag("system"); Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }
            Picker("Default start page", selection: $p.startPage) { Text("Home").tag(0); Text("Library").tag(1); Text("Browse").tag(2); Text("News").tag(3); Text("Profile").tag(4) }
            Picker("Default title language", selection: $p.titleLanguage) { Text("Automatic").tag("auto"); Text("简体中文").tag("zh"); Text("English").tag("en"); Text("Original").tag("native") }
            Toggle("Auto-suggest in Browse", isOn: $p.browseSuggestions)
            Toggle("Auto-suggest in Library", isOn: $p.librarySuggestions)
        }.navigationTitle("General")
    }
}
struct ContentSettingsView: View {
    @Environment(Preferences.self) private var preferences
    var body: some View {
        @Bindable var p = preferences
        Form {
            Picker("Rating slider step", selection: $p.ratingStep) { ForEach([1.0, 5, 10, 20, 25], id: \.self) { Text(ReadingNumber.string($0)).tag($0) } }
            Picker("Add to library default", selection: $p.defaultState) { ForEach(ReadingStatus.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) } }
            NavigationLink("Content rating preferences") { ContentRatingSettingsView() }
            Toggle("Hide library series", isOn: $p.hideLibrary)
            Text("Exclude series already in your library from browse results and Mix.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Content")
    }
}
struct ContentRatingSettingsView: View {
    @Environment(Preferences.self) private var preferences
    var body: some View {
        Form {
            Section { Text("Choose visible ratings and blur covers separately. Your cloud records and statistics are kept.").font(.footnote) }
            ForEach(Array(Preferences.ratings.enumerated()), id: \.element) { index, rating in
                Section(LocalizedStringKey(Preferences.ratingNames[index])) {
                    Toggle("Show content", isOn: Binding(get: { preferences.visibleRatings.contains(rating) }, set: { value in
                        if value { if !preferences.visibleRatings.contains(rating) { preferences.visibleRatings.append(rating) } }
                        else if preferences.visibleRatings.count > 1 { preferences.visibleRatings.removeAll { $0 == rating } }
                    })).disabled(preferences.visibleRatings == [rating])
                    Toggle("Blur covers", isOn: Binding(get: { preferences.blurredRatings.contains(rating) }, set: { value in
                        if value { if !preferences.blurredRatings.contains(rating) { preferences.blurredRatings.append(rating) } } else { preferences.blurredRatings.removeAll { $0 == rating } }
                    }))
                }
            }
        }.navigationTitle("Content rating preferences")
    }
}
