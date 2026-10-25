import SwiftUI
import SafariServices
import Observation
import SwiftData

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
    func text(_ key: String) -> String {
        let code = locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

@main struct MangaBakaNativeApp: App {
    @State private var preferences = Preferences()
    @State private var auth: AuthSession
    @State private var library: LibraryRepository
    private let container: ModelContainer
    init() {
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            #if DEBUG && targetEnvironment(simulator)
            let container = try ModelContainer(for: LibraryCache.self, configurations: ModelConfiguration(isStoredInMemoryOnly: AccountReviewFixtures.enabled))
            #else
            let container = try ModelContainer(for: LibraryCache.self)
            #endif
            self.container = container
            #if DEBUG && targetEnvironment(simulator)
            let auth = AccountReviewFixtures.enabled ? AccountReviewFixtures.session() : AuthSession()
            #else
            let auth = AuthSession()
            #endif
            _auth = State(initialValue: auth)
            _library = State(initialValue: LibraryRepository(auth: auth, context: container.mainContext))
        } catch { fatalError("Unable to open library cache: \(error)") }
    }
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if let id = ProcessInfo.processInfo.environment["M2_DETAIL"] {
                    NavigationStack { SeriesDetailView(id: id) }
                } else { RootView() }
            }.environment(preferences).environment(auth).environment(library)
                .modelContainer(container)
                .sheet(isPresented: Binding(get: { auth.showingSignIn }, set: { auth.showingSignIn = $0 })) { PATSignInView() }
                .task(id: auth.generation) { library.activate(); if auth.isAuthenticated { await library.sync() } }
                .onChange(of: scenePhase) { if scenePhase == .active { Task { await library.sync() } } }
                .alert("Account", isPresented: Binding(get: { auth.error != nil }, set: { if !$0 { auth.error = nil } })) { Button("OK") { auth.error = nil } } message: { Text(LocalizedStringKey(auth.error ?? "")) }
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
            NavigationStack { LibraryView() }.tabItem { Label("Library", systemImage: "bookmark") }.tag(1)
            NavigationStack { PendingView(title: "Browse", icon: "safari") }.tabItem { Label("Browse", systemImage: "safari") }.tag(2)
            NavigationStack { PendingView(title: "News", icon: "newspaper") }.tabItem { Label("News", systemImage: "newspaper") }.tag(3)
            NavigationStack { ProfileView()
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
