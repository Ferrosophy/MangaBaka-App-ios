import SwiftUI
import SafariServices
import Observation

@Observable final class Preferences {
    private let defaults: UserDefaults
    var language: String { didSet { defaults.set(language, forKey: "language") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: "language") ?? "system"
        appearance = defaults.string(forKey: "appearance") ?? "system"
    }
    var locale: Locale {
        if language != "system" { return Locale(identifier: language) }
        return Locale(identifier: Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en")
    }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    func text(_ key: String) -> String { String(localized: String.LocalizationValue(key), locale: locale) }
}

@main struct MangaBakaNativeApp: App {
    @State private var preferences = Preferences()
    var body: some Scene {
        WindowGroup {
            RootView().environment(preferences)
                .environment(\.locale, preferences.locale)
                .preferredColorScheme(preferences.colorScheme)
                .tint(.green)
        }
    }
}

struct WebPage: Identifiable { let id = UUID(); let url: URL }
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct RootView: View {
    @Environment(Preferences.self) private var preferences
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack { PendingView(title: "Library", icon: "bookmark") }.tabItem { Label("Library", systemImage: "bookmark") }.tag(1)
            NavigationStack { PendingView(title: "Browse", icon: "safari") }.tabItem { Label("Browse", systemImage: "safari") }.tag(2)
            NavigationStack { PendingView(title: "News", icon: "newspaper") }.tabItem { Label("News", systemImage: "newspaper") }.tag(3)
            NavigationStack {
                List {
                    Section { Label("MangaBaka Native", systemImage: "books.vertical"); Text("Your next discovery starts here.").foregroundStyle(.secondary) }
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }.navigationTitle("Profile")
            }.tabItem { Label("Profile", systemImage: "person") }.tag(4)
        }
    }
}
struct PendingView: View {
    let title: LocalizedStringKey
    let icon: String
    var body: some View {
        ContentUnavailableView("Coming in a future update", systemImage: icon, description: Text("Explore the home page while we build this feature."))
            .navigationTitle(title)
    }
}
