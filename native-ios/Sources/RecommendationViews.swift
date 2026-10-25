import SwiftUI

struct MixView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AuthSession.self) private var auth
    @State private var seeds: [HomeCard] = []
    @State private var strict = false
    @State private var blend = false
    @State private var picking = false
    @State private var list = DiscoveryList()
    @State private var seedSuggestions = DiscoveryList()
    @State private var warning: String?
    private var key: String { seeds.map(\.id).joined(separator: ",") + "|\(strict)|\(blend)|\(preferences.policyKey)|\(auth.generation)" }
    var body: some View {
        @Bindable var settings = preferences
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Seeds").font(.title2.bold())
                Button("Add a series…", systemImage: "magnifyingglass") { picking = true }.buttonStyle(.bordered).disabled(seeds.count >= 25)
                if !seeds.isEmpty {
                    ForEach(seeds) { card in HStack { Text(preferences.title(card)); Spacer(); Button("Remove", systemImage: "minus.circle") { seeds.removeAll { $0.id == card.id } }.labelStyle(.iconOnly) } }
                    Button("Clear seeds", role: .destructive) { seeds = [] }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Strict mode", isOn: $strict)
                    Text("Hard-filter tags instead of vector boost").font(.caption).foregroundStyle(.secondary)
                    Divider(); Toggle("Hide library series", isOn: $settings.hideLibrary)
                    Divider(); Toggle("Blend my taste", isOn: $blend)
                }.padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 24))
                if let warning { Text(LocalizedStringKey(warning)).foregroundStyle(.secondary) }
                if seeds.isEmpty { ContentUnavailableView("Start your mix", systemImage: "shuffle", description: Text("Add series as seeds to discover recommendations tailored to your taste.")) }
                else {
                    if !list.dna.isEmpty { Text("Shared traits").font(.headline); Text(list.dna.prefix(12).map { $0.text("name") }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    DiscoveryCards(cards: list.cards.filter { c in !seeds.contains { $0.id == c.id } }, excludeLibrary: preferences.hideLibrary)
                    DiscoveryFooter(list: list) { await load() }
                    if !seedSuggestions.cards.isEmpty {
                        Text("Suggested seeds").font(.headline)
                        ForEach(seedSuggestions.cards.filter { c in !seeds.contains { $0.id == c.id } }.prefix(6)) { card in Button { add(card) } label: { Label(preferences.title(card), systemImage: "plus.circle") }.disabled(seeds.count >= 25) }
                    }
                }
            }.padding()
        }.navigationTitle("Mix")
            .sheet(isPresented: $picking) { NavigationStack { SeedPicker { add($0); picking = false } } }
            .task(id: key) {
                list.reset(); seedSuggestions.reset(); warning = nil
                guard !seeds.isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() } catch { return }
                await load(refresh: true)
                guard !Task.isCancelled, seeds.count >= 2 else { return }
                await seedSuggestions.load(path: "v1/series/mix/seeds", items: seeds.map { URLQueryItem(name: "series", value: $0.id) })
            }
            .refreshable { if !seeds.isEmpty { await load(refresh: true) } }
            .onChange(of: blend) { if blend && !auth.isAuthenticated { blend = false; auth.showingSignIn = true } }
    }
    private func add(_ card: HomeCard) { if seeds.count < 25 && !seeds.contains(where: { $0.id == card.id }) { seeds.append(card) } }
    private func load(refresh: Bool = false) async {
        let expected = key
        var items = seeds.map { URLQueryItem(name: "series", value: $0.id) }
        items += [URLQueryItem(name: "strict", value: String(strict)), URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "schema", value: "full")]
        items += preferences.visibleRatings.map { URLQueryItem(name: "content_rating", value: $0) }
        if preferences.hideLibrary, let id = auth.profile?.id { items.append(URLQueryItem(name: "exclude_user_library", value: id)) }
        if blend {
            guard auth.isAuthenticated, let id = auth.profile?.id else { warning = "Sign in to blend your taste."; return }
            do {
                let data = try await recommendationStatus(auth)
                guard key == expected else { return }
                if data.cold { warning = "Your taste profile is not ready. Add more series to your library first."; return }
                if data.stale { warning = "Your taste profile is updating." }
                items.append(URLQueryItem(name: "blend_user_id", value: id))
            } catch { if key == expected { warning = "Unable to load this section" }; return }
        }
        guard key == expected else { return }
        await list.load(path: "v2/series/mix", items: items, refresh: refresh)
    }
}
struct SeedPicker: View {
    let choose: (HomeCard) -> Void
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var list = DiscoveryList()
    var body: some View {
        List {
            ForEach(list.cards.filter { preferences.allows($0.contentRating) }) { card in Button { choose(card) } label: { HStack { PolicyCover(url: card.image, rating: card.contentRating).frame(width: 40, height: 60).clipped(); Text(preferences.title(card)); Spacer(); Image(systemName: "plus.circle") } } }
            DiscoveryFooter(list: list) { await load() }
        }.navigationTitle("Add a series…").searchable(text: $query, prompt: "Search series")
            .toolbar { Button("Cancel") { dismiss() } }
            .task(id: query) {
                list.reset(); guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() } catch { return }
                await load(refresh: true)
            }
    }
    private func load(refresh: Bool = false) async { await list.load(path: "v2/series/search", items: BrowseQuery(text: query, sort: "relevance_desc").items(page: 1, preferences: preferences, account: nil), refresh: refresh) }
}
struct RecommendationReadiness {
    let cold: Bool
    let stale: Bool
    static func decode(_ data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let row = root["data"] as? [String: Any] ?? root
        guard let cold = row["cold_start"] as? Bool else { throw URLError(.cannotParseResponse) }
        return Self(cold: cold, stale: row["profile_stale"] as? Bool ?? false)
    }
}
@MainActor func recommendationStatus(_ auth: AuthSession) async throws -> RecommendationReadiness {
    #if DEBUG && targetEnvironment(simulator)
    if ProcessInfo.processInfo.environment["M4_FIXTURES"] == "1" { return RecommendationReadiness(cold: true, stale: false) }
    #endif
    return try RecommendationReadiness.decode(await auth.request(path: "my/series/recommendations/status"))
}
struct DiscoveryQueueView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(LibraryRepository.self) private var library
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [HomeCard] = []
    @State private var index = 0
    @State private var added = 0
    @State private var loading = false
    @State private var writing = false
    @State private var loaded = false
    @State private var cold = false
    @State private var stale = false
    @State private var failure: String?
    @State private var confirmCompleted = false
    @State private var queueKey = ""
    private var current: HomeCard? { cards.indices.contains(index) ? cards[index] : nil }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !auth.isAuthenticated { LoginRequiredView() }
                else if loading { ProgressView() }
                else if cold {
                    ContentUnavailableView("Discovery queue", systemImage: "sparkles", description: Text("Your taste profile is not ready. Add more series to your library first."))
                    Button("Back") { dismiss() }.buttonStyle(.borderedProminent)
                } else if let card = current {
                    Text("\(index + 1) / \(cards.count)").foregroundStyle(.secondary)
                    NavigationLink { SeriesDetailView(id: card.id, preview: card) } label: { DiscoveryTile(card: card).frame(maxWidth: 240) }.buttonStyle(.plain)
                    HStack {
                        Button("Skip") { index += 1 }
                        Button("Not interested") { if let id = auth.profile?.id { preferences.dismissSeries(card.id, account: id) }; index += 1 }
                    }.disabled(writing)
                    Button("Add to library") { add(defaultStatus) }.buttonStyle(.borderedProminent).disabled(!library.canWrite || writing)
                    Menu("Choose reading status") { ForEach(ReadingStatus.allCases) { state in Button(LocalizedStringKey(state.title)) { add(state) } } }.disabled(!library.canWrite || writing)
                    if !library.canWrite { SyncBanner(); Button("Sync before editing") { Task { await library.sync() } }.disabled(library.syncing) }
                } else if loaded && failure == nil {
                    ContentUnavailableView(cards.isEmpty ? "No recommendations yet" : "Queue complete", systemImage: "checkmark.circle")
                    Text("Reviewed: \(index) · Added: \(added)")
                    Button("Start again") { Task { await start() } }.buttonStyle(.borderedProminent)
                }
                if stale { Text("Your taste profile is updating.").font(.caption).foregroundStyle(.secondary) }
                if let failure { Text(LocalizedStringKey(failure)); if current == nil { Button("Retry") { Task { await start() } } } }
            }.padding().frame(maxWidth: .infinity)
        }.navigationTitle("Discovery queue")
            .task(id: "\(auth.generation)|\(preferences.policyKey)") {
                let key = "\(auth.generation)|\(preferences.policyKey)"
                if queueKey != key || !loaded { queueKey = key; await start() }
            }
            .confirmationDialog("Mark as completed?", isPresented: $confirmCompleted, titleVisibility: .visible) { Button("Complete and fill known progress") { save(.completed, fill: true) } }
    }
    private var defaultStatus: ReadingStatus { ReadingStatus(rawValue: preferences.defaultState) ?? .planToRead }
    private func add(_ state: ReadingStatus) { if state == .completed { confirmCompleted = true } else { save(state) } }
    private func save(_ state: ReadingStatus, fill: Bool = false) {
        guard let card = current, !writing else { return }
        writing = true; failure = nil
        let epoch = auth.generation
        Task {
            defer { writing = false }
            do {
                // Fetch full metadata before writing so completion can fill known totals.
                let data = try await DiscoveryAPI.shared.get("v1/series/" + card.id)
                guard auth.generation == epoch else { return }
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let row = root?["data"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
                var entry = LibraryEntry.draft(series: DetailRecord(row), state: state)
                if fill { entry.chapters = entry.totalChapters ?? 0; entry.volumes = entry.totalVolumes ?? 0 }
                try await library.save(entry, create: true)
                guard auth.generation == epoch else { return }
                added += 1; index += 1
            } catch { if auth.generation == epoch { failure = library.friendly(error) } }
        }
    }
    private func start() async {
        cards = []; index = 0; added = 0; failure = nil; loaded = false; cold = false; stale = false
        guard auth.isAuthenticated, let account = auth.profile?.id else { return }
        let epoch = auth.generation
        loading = true
        defer { if auth.generation == epoch { loading = false } }
        do {
            let state = try await recommendationStatus(auth)
            guard auth.generation == epoch, !Task.isCancelled else { return }
            cold = state.cold; stale = state.stale
            if cold { loaded = true; return }
            var items = [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "exclude_user_library", value: account), URLQueryItem(name: "random_seed", value: String(Double.random(in: 0..<1)))]
            items += preferences.visibleRatings.map { URLQueryItem(name: "content_rating", value: $0) }
            items += preferences.dismissed(account).sorted().prefix(100).map { URLQueryItem(name: "exclude_ids", value: $0) }
            let url = DiscoveryAPI.url("v1/my/series/recommendations", items)
            let data = try await auth.request(path: "my/series/recommendations?" + (url.query ?? ""))
            guard auth.generation == epoch, !Task.isCancelled else { return }
            cards = try DetailPage.decode(data).records.compactMap { $0.object("series").card ?? $0.card }.filter { preferences.allows($0.contentRating) && !preferences.dismissed(account).contains($0.id) }
            let existing = Set(library.entries.map(\.id)); cards.removeAll { existing.contains($0.id) }
            loaded = true
        } catch { if auth.generation == epoch { failure = library.friendly(error) } }
    }
}
