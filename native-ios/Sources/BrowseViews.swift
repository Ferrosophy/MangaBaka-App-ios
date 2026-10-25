import SwiftUI

struct BrowseView: View {
    static let types = [("manga", "Manga"), ("manhwa", "Manhwa"), ("manhua", "Manhua"), ("novel", "Novels"), ("oel-other", "OEL / Other")]
    var body: some View {
        List {
            Section {
                NavigationLink { BrowseResultsView(title: "Search", query: BrowseQuery()) } label: { Label("Search", systemImage: "magnifyingglass") }
                NavigationLink { MixView() } label: { Label("Mix", systemImage: "shuffle") }
                NavigationLink { DiscoveryQueueView() } label: { Label("Discovery queue", systemImage: "sparkles") }
            }
            ForEach(Self.types, id: \.0) { type in
                Section(LocalizedStringKey(type.1)) {
                    ForEach([("popularity_asc", "Most popular"), ("score_desc", "Top community rated"), ("random", "Random")], id: \.0) { sort in
                        NavigationLink(LocalizedStringKey(sort.1)) { BrowseResultsView(title: sort.1, query: BrowseQuery(type: type.0, sort: sort.0), ranked: sort.0 != "random") }
                    }
                }
            }
        }.navigationTitle("Browse")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") } }
    }
}
struct DiscoveryTile: View {
    let card: HomeCard
    var rank: Int? = nil
    @Environment(Preferences.self) private var preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PolicyCover(url: card.image, rating: card.contentRating).aspectRatio(2/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) { if let rank { Text("\(rank)").font(.headline).padding(8).background(.green, in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomTrailingRadius: 12)).foregroundStyle(.black) } }
            Text(preferences.title(card)).font(.subheadline.bold()).lineLimit(2, reservesSpace: true)
        }.accessibilityElement(children: .combine)
    }
}
struct DiscoveryCards: View {
    let cards: [HomeCard]
    var ranked = false
    var excludeLibrary = false
    @Environment(Preferences.self) private var preferences
    @Environment(LibraryRepository.self) private var library
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], alignment: .leading, spacing: 20) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                if preferences.allows(card.contentRating) && (!excludeLibrary || !library.entries.contains { $0.id == card.id }) {
                    NavigationLink { SeriesDetailView(id: card.id, preview: card) } label: { DiscoveryTile(card: card, rank: ranked ? index + 1 : nil) }.buttonStyle(.plain).accessibilityIdentifier("discovery-card-\(card.id)")
                }
            }
        }
    }
}
struct DiscoveryFooter: View {
    let list: DiscoveryList
    let load: () async -> Void
    var body: some View {
        if list.loading { ProgressView().frame(maxWidth: .infinity).padding() }
        else if list.failed { Button("Unable to load this section. Retry") { Task { await load() } } }
        else if list.hasNext { Button("Load more") { Task { await load() } }.frame(minHeight: 44) }
        else if list.rows.isEmpty && list.loaded { ContentUnavailableView("No results found", systemImage: "magnifyingglass") }
    }
}
struct BrowseResultsView: View {
    let title: String
    @State var query: BrowseQuery
    var ranked = false
    @State private var list = DiscoveryList()
    @State private var suggestions = DiscoveryList()
    @Environment(LibraryRepository.self) private var library
    @State private var genres: [DetailRecord] = []
    @State private var showingFilters = false
    @Environment(Preferences.self) private var preferences
    @Environment(AuthSession.self) private var auth
    private var key: String { "\(query.text)|\(query.type)|\(query.status)|\(query.tag)|\(query.sort)|\(preferences.policyKey)|\(auth.generation)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !query.type.isEmpty || !query.status.isEmpty || !query.tag.isEmpty {
                    Text([query.type, query.status, genres.first { $0.id == query.tag }?.text("name") ?? query.tag].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    Button("Clear filters") { query.type = ""; query.status = ""; query.tag = "" }
                }
                DiscoveryCards(cards: list.cards, ranked: ranked && query.text.isEmpty, excludeLibrary: preferences.hideLibrary)
                DiscoveryFooter(list: list) { await load() }
            }.padding()
        }.navigationTitle(LocalizedStringKey(title))
            .searchable(text: $query.text, prompt: "Search series")
            .searchSuggestions {
                if preferences.browseSuggestions && !query.text.isEmpty {
                    ForEach(Array(preferences.visible(suggestions.cards, excluding: preferences.hideLibrary ? Set(library.entries.map(\.id)) : []).prefix(8))) { card in Text(preferences.title(card)).searchCompletion(preferences.title(card)) }
                }
            }
            .toolbar { Button("Filters", systemImage: "line.3.horizontal.decrease") { showingFilters = true } }
            .sheet(isPresented: $showingFilters) { NavigationStack { filters } }
            .task(id: key) {
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() } catch { return }
                list.reset(); await load(refresh: true)
            }
            .task(id: query.text + "\(preferences.browseSuggestions)") {
                suggestions.reset()
                guard preferences.browseSuggestions, !query.text.isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() } catch { return }
                var q = BrowseQuery(text: query.text, sort: "relevance_desc")
                q.type = query.type
                await suggestions.load(path: "v2/series/search", items: q.items(page: 1, preferences: preferences, account: auth.profile?.id))
            }
            .safeRefreshable { query.randomSeed = Double.random(in: 0..<1); await load(refresh: true) }
    }
    private func load(refresh: Bool = false) async {
        var q = query
        if !q.text.isEmpty && q.sort == "popularity_asc" { q.sort = "relevance_desc" }
        await list.load(path: "v2/series/search", items: q.items(page: 1, preferences: preferences, account: auth.profile?.id), refresh: refresh)
    }
    private var filters: some View {
        Form {
            Picker("Type", selection: $query.type) { Text("Any").tag(""); ForEach(BrowseView.types, id: \.0) { Text(LocalizedStringKey($0.1)).tag($0.0) } }
            Picker("Status", selection: $query.status) { Text("Any").tag(""); ForEach(["releasing", "completed", "hiatus", "cancelled", "upcoming", "unknown"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }
            Picker("Genre", selection: $query.tag) { Text("Any").tag(""); ForEach(genres) { Text($0.text("name")).tag($0.id) } }
            Picker("Sort by", selection: $query.sort) { ForEach([("popularity_asc", "Most popular"), ("score_desc", "Top community rated"), ("relevance_desc", "Relevance"), ("latest", "Latest"), ("random", "Random")], id: \.0) { Text(LocalizedStringKey($0.1)).tag($0.0) } }
            Button("Clear filters") { query = BrowseQuery() }
        }.navigationTitle("Filters")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } } }
            .task {
                do {
                    let data = try await DiscoveryAPI.shared.get("v1/tags", items: [URLQueryItem(name: "is_genre", value: "true"), URLQueryItem(name: "limit", value: "100")])
                    genres = try DetailPage.decode(data).records.sorted { $0.text("name") < $1.text("name") }
                } catch { genres = []; }
            }
    }
}
struct NewsView: View {
    @State private var list = DiscoveryList()
    @State private var web: WebPage?
    @Environment(Preferences.self) private var preferences
    @Environment(\.locale) private var locale
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(list.rows) { record in article(NewsArticle(record: record)) }
                DiscoveryFooter(list: list) { await load() }
            }.padding()
        }.navigationTitle("News")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") } }
            .task { if !list.loaded { await load() } }
            .safeRefreshable { await load(refresh: true) }
            .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
    }
    private func load(refresh: Bool = false) async { await list.load(path: "v2/news", items: [URLQueryItem(name: "limit", value: "10")], refresh: refresh) }
    private func article(_ article: NewsArticle) -> some View {
        let r = article.record
        let visible = article.series.filter { preferences.allows($0.contentRating) }
        return VStack(alignment: .leading, spacing: 16) {
            Button { if let url = article.url { web = WebPage(url: url) } } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(r.text("source_name") == "ann" ? "ANIME NEWS NETWORK" : r.text("source_name").uppercased()).font(.caption.bold()).padding(8).background(.quaternary, in: Capsule()); Spacer(); Text(localDate(r.text("published_at"), locale: locale)).font(.caption); Image(systemName: "arrow.up.right.square") }
                    Text(r.text("title")).font(.headline)
                    if !r.text("author").isEmpty { Text(r.text("author")).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).disabled(article.url == nil).accessibilityLabel(Text(r.text("title")))
            if article.total > 0 {
                HStack { Text("Referenced series"); Text("\(visible.count) / \(article.total)") }.font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) { LazyHStack(alignment: .top, spacing: 12) { ForEach(visible) { card in NavigationLink { SeriesDetailView(id: card.id, preview: card) } label: { DiscoveryTile(card: card).frame(width: 100) }.buttonStyle(.plain) } }.scrollTargetLayout() }.scrollClipDisabled().scrollTargetBehavior(.viewAligned)
            }
        }.padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 24))
    }
}
