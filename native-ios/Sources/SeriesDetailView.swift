import SwiftUI

struct SeriesDetailView: View {
    let preview: HomeCard?
    @State private var model: DetailModel
    @State private var selected: DetailTab = .info
    @State private var gallery: GalleryItem?
    @State private var galleryItems: [GalleryItem] = []
    @State private var web: WebPage?
    @State private var scrollPosition = ScrollPosition(y: 0)
    @State private var offsets: [DetailTab: CGFloat] = [:]
    @State private var restoringScroll = false
    @State private var compactTitle = false
    @Environment(\.locale) private var locale
    @Environment(Preferences.self) private var preferences
    init(id: String, preview: HomeCard? = nil) { self.preview = preview; _model = State(initialValue: DetailModel(id: id)) }
    private var title: String { model.series?.card?.displayTitle(locale: locale) ?? preview?.displayTitle(locale: locale) ?? preferences.text("Series") }
    private var cover: URL? { model.series?.cover ?? preview?.image }
    private var originalCover: URL? { model.series?.fullSizeCoverCandidates.first ?? cover }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                hero
                Section {
                    VStack(alignment: .leading, spacing: 24) {
                        if let failure = model.failure { ContentUnavailableView { Label(LocalizedStringKey(failure), systemImage: "exclamationmark.triangle") } actions: { Button("Retry") { Task { await model.load() } } } }
                        content(selected)
                    }.padding(20)
                } header: { tabBar }
            }.padding(.bottom, 24)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            compactTitle = offset > 180
            if !restoringScroll { offsets[selected] = max(0, offset) }
        }
        .refreshable {
            await model.load(refresh: true)
            await model.lists[selected]?.load(refresh: true)
            if selected == .similar { await model.readers.load(refresh: true) }
        }
        .navigationTitle(compactTitle ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: URL(string: "https://mangabaka.org/\(model.seriesID)")!) } }
        .task { await model.load(); await loadSelected() }
        .task { await model.loadTaxonomy() }
        .task(id: selected) { await loadSelected() }
        .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
        .fullScreenCover(item: $gallery) { item in ImageViewer(items: galleryItems, selected: item.id) }
        .accessibilityIdentifier("series-detail")
    }
    private func selectTab(_ tab: DetailTab) {
        guard selected != tab else { return }
        let target = offsets[tab] ?? 0
        restoringScroll = true
        selected = tab
        Task { @MainActor in
            await Task.yield()
            scrollPosition.scrollTo(y: target)
            await Task.yield()
            restoringScroll = false
        }
    }
    private func loadSelected() async {
        if let list = model.lists[selected], !list.loaded { await list.load() }
        if selected == .similar, !model.readers.loaded { await model.readers.load() }
    }
    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            Button { if let cover { showGallery([GalleryItem(id: "hero", urls: [originalCover ?? cover], title: title)], index: 0) } } label: {
                CandidateImage(urls: cover.map { [$0] } ?? []).frame(width: 120, height: 180).clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityLabel(Text("Preview cover"))
            VStack(alignment: .leading, spacing: 10) {
                if let s = model.series {
                    HStack { Text(LocalizedStringKey(s.text("type"))).textCase(.uppercase); Text("·"); Text(LocalizedStringKey(s.text("status"))); if let score = s.score { Text("★ \(score, specifier: "%.1f")") } }
                        .font(.caption.bold()).foregroundStyle(.green)
                }
                Text(title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                if let s = model.series {
                    let alternate = s.text("native_title")
                    if !alternate.isEmpty && alternate != title { Text(alternate).foregroundStyle(.secondary) }
                    let authors = s.names("authors"), artists = s.names("artists")
                    if authors == artists && !authors.isEmpty { Text("Story & art: \(authors)").font(.subheadline) }
                    else {
                        if !authors.isEmpty { Text("Story: \(authors)").font(.subheadline) }
                        if !artists.isEmpty { Text("Art: \(artists)").font(.subheadline) }
                    }
                } else if model.loading { ProgressView() }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).padding(.top, 16)
        .background {
            GeometryReader { g in
                if let cover { CoverImage(url: cover).frame(width: g.size.width, height: g.size.height).blur(radius: 35).opacity(0.22).clipped().mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)) }
            }.accessibilityHidden(true)
        }
    }
    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DetailTab.allCases) { tab in
                        Button { selectTab(tab) } label: {
                            Text(LocalizedStringKey(tab.rawValue)).font(.subheadline.bold()).padding(.horizontal, 16).frame(minHeight: 44)
                                .background(selected == tab ? Color.green.opacity(0.22) : .clear, in: Capsule())
                        }.buttonStyle(.plain).id(tab).accessibilityIdentifier("detail-tab-\(tab.rawValue)").accessibilityAddTraits(selected == tab ? .isSelected : [])
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }.background(.regularMaterial).accessibilityIdentifier("detail-tabs")
            .onChange(of: selected) { withAnimation { proxy.scrollTo(selected, anchor: .center) } }
        }
    }
    @ViewBuilder private func content(_ tab: DetailTab) -> some View {
        if tab == .info {
            if let series = model.series { SeriesInfoView(series: series, links: model.lists[.info]?.rows ?? [], tagPaths: model.tagPaths, openURL: { web = WebPage(url: $0) }) }
        } else if let list = model.lists[tab] {
            Text(LocalizedStringKey(tab.rawValue)).font(.headline)
            if tab == .covers { covers(list.rows) }
            else if tab == .related { SeriesGrid(records: list.rows, currentID: model.seriesID, columns: 2) }
            else if tab == .similar { SimilarContent(list: list, readers: model.readers, currentID: model.seriesID) }
            else if tab == .news { news(list.rows) }
            else if tab == .collections { ForEach(list.rows) { collection in NavigationLink { CollectionWorksView(collection: collection, fallback: originalCover) } label: { CollectionSummary(record: collection) }.buttonStyle(.plain).accessibilityIdentifier("collection-\(collection.id)") } }
            else if tab == .works { WorksContent(rows: list.rows, fallback: originalCover) }
            if tab != .similar { ListStatus(list: list) }
        }
    }
    private func covers(_ rows: [DetailRecord]) -> some View {
        let items: [GalleryItem] = rows.enumerated().map { index, row in
            let raw = ImageCandidates.urls(row.object("image").values["raw"])
            let urls = raw + row.coverCandidates.filter { !raw.contains($0) }
            let caption = [row.text("language").uppercased(), preferences.text(row.text("type")), row.text("index")].filter { !$0.isEmpty }.joined(separator: " · ")
            return GalleryItem(id: "\(index)-\(row.id)", urls: urls, title: caption, thumbnail: row.coverCandidates)
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 12)], spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { showGallery(items, index: index) } label: {
                    VStack(alignment: .leading) { CandidateImage(urls: item.thumbnail).aspectRatio(2/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10)); Text(item.title).font(.caption).lineLimit(2) }
                }.buttonStyle(.plain).disabled(item.urls.isEmpty).accessibilityIdentifier("cover-card-\(index)")
            }
        }
    }
    private func news(_ rows: [DetailRecord]) -> some View {
        ForEach(rows.sorted { $0.text("published_at") > $1.text("published_at") }) { row in
            Button { if let url = URL(string: row.text("url")), ["https", "http"].contains(url.scheme ?? "") { web = WebPage(url: url) } } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(row.text("source_name").uppercased()).font(.caption.bold()); Spacer(); Text(localDate(row.text("published_at"), locale: locale)).font(.caption).foregroundStyle(.secondary); Image(systemName: "arrow.up.right") }
                    Text(row.text("title")).font(.headline).lineLimit(3)
                    if !row.text("author").isEmpty { Text(row.text("author")).font(.subheadline).foregroundStyle(.secondary) }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
            }.buttonStyle(.plain)
        }
    }
    private func showGallery(_ items: [GalleryItem], index: Int) { guard items.indices.contains(index) else { return }; galleryItems = items; gallery = items[index] }
}
func localDate(_ raw: String, locale: Locale) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0)
    guard let d = f.date(from: String(raw.prefix(10))) else { return raw }
    f.locale = locale; f.dateStyle = .medium; f.timeStyle = .none; return f.string(from: d)
}
struct ListStatus: View {
    let list: DetailList
    var body: some View {
        if list.loading { ProgressView().frame(maxWidth: .infinity).padding() }
        else if list.failed { Button("Unable to load this section. Retry") { Task { await list.load() } }.frame(minHeight: 44) }
        else if list.loaded && list.rows.isEmpty { ContentUnavailableView("Nothing here yet", systemImage: "books.vertical") }
        else if list.hasNext { Button("Load more") { Task { await list.load() } }.frame(minHeight: 44) }
    }
}
struct SeriesGrid: View {
    let records: [DetailRecord]
    let currentID: String
    var columns = 3
    var listStyle = false
    @Environment(\.locale) private var locale
    @Environment(Preferences.self) private var preferences
    var body: some View {
        let cards = cards()
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: listStyle ? 1 : columns), alignment: .leading, spacing: 18) {
            ForEach(cards) { card in
                NavigationLink { SeriesDetailView(id: card.id, preview: card) } label: {
                    if listStyle { HStack { CoverImage(url: card.image).frame(width: 60, height: 90).clipShape(RoundedRectangle(cornerRadius: 8)); Text(card.displayTitle(locale: locale)).frame(maxWidth: .infinity, alignment: .leading) } }
                    else { VStack(alignment: .leading) { CandidateImage(urls: card.image.map { [$0] } ?? []).aspectRatio(2/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10)); Text(card.displayTitle(locale: locale)).font(.caption.weight(.semibold)).lineLimit(2); if let relation = relation(card.id) { Text(preferences.text(relation)).font(.caption).foregroundStyle(.secondary) } } }
                }.buttonStyle(.plain).accessibilityIdentifier("series-card-\(card.id)")
            }
        }
    }
    private func relation(_ id: String) -> String? {
        let value = records.first { $0.object("series").id == id }?.text("relation_type") ?? ""
        return value.isEmpty ? nil : value
    }
    private func cards() -> [HomeCard] {
        var seen = Set<String>()
        return records.compactMap { ($0.values["series"] as? [String: Any]).flatMap { HomeCard.parse($0, shelf: .trending) } ?? $0.card }.filter { $0.id != currentID && seen.insert($0.id).inserted }
    }
}
struct SimilarContent: View {
    let list: DetailList
    let readers: DetailList
    let currentID: String
    @AppStorage("similarList") private var listStyle = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { listStyle.toggle() } label: { Label("Change layout", systemImage: listStyle ? "square.grid.3x3" : "list.bullet") }.frame(minHeight: 44)
            SeriesGrid(records: list.rows, currentID: currentID, listStyle: listStyle)
            ListStatus(list: list)
            Text("Readers also like").font(.headline)
            SeriesGrid(records: readers.rows, currentID: currentID, listStyle: listStyle)
            ListStatus(list: readers)
        }
    }
}
