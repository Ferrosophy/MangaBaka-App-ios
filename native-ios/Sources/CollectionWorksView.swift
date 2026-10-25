import SwiftUI

struct CollectionSummary: View {
    let record: DetailRecord
    @Environment(Preferences.self) private var preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(record.text("title")).font(.headline)
                Spacer()
                if let count = Int(record.text("count_main")) { Text("\(count) volumes").font(.caption.bold()).foregroundStyle(.green) }
            }
            Text([record.object("publisher").text("name"), record.object("edition").text("name"), record.object("language").text("language")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            FlowLayout { ForEach(["format", "medium", "status"], id: \.self) { key in
                if !record.text(key).isEmpty { Text(preferences.text(record.text(key))).font(.caption.bold()).padding(6).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6)) }
            } }
        }.detailCard()
    }
}
struct CollectionWorksView: View {
    let collection: DetailRecord
    let fallback: URL?
    @State private var list: DetailList
    init(collection: DetailRecord, fallback: URL?) {
        self.collection = collection; self.fallback = fallback
        _list = State(initialValue: DetailList(path: "v1/collections/\(collection.id)/works"))
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                CollectionSummary(record: collection)
                WorksContent(rows: list.rows, fallback: fallback, forceGrid: true)
                ListStatus(list: list)
            }.padding(20)
        }.navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { if !list.loaded { await list.load() } }
        .safeRefreshable { await list.load(refresh: true) }
    }
}
struct WorksContent: View {
    let rows: [DetailRecord]
    let fallback: URL?
    var forceGrid = false
    @AppStorage("worksGrid") private var grid = false
    @Environment(\.locale) private var locale
    @Environment(Preferences.self) private var preferences
    @State private var gallery: GalleryPresentation?
    private var items: [GalleryItem] {
        rows.map { row in
            let label = row.text("sub_title").isEmpty ? String(format: preferences.text("Volume %@"), row.text("sequence_string")) : row.text("sub_title")
            let urls = row.fullSizeWorkImages + (fallback.map { [$0] } ?? [])
            return GalleryItem(id: row.id, urls: urls, title: label, thumbnail: row.workImages + (fallback.map { [$0] } ?? []))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !forceGrid { Button { grid.toggle() } label: { Label("Change layout", systemImage: grid ? "list.bullet" : "square.grid.2x2") }.frame(minHeight: 44) }
            UniformGrid(columns: grid || forceGrid ? 2 : 1, spacing: 14, rowSpacing: 14) { width in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let item = items[index]
                    Button { if !item.urls.isEmpty { gallery = GalleryPresentation(items: items, selectedID: item.id) } } label: {
                        if grid || forceGrid { VStack(alignment: .leading, spacing: 8) {
                            CandidateImage(urls: item.thumbnail).aspectRatio(2/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                            metadata(row, title: item.title)
                        } } else {
                            HStack(alignment: .top, spacing: 14) {
                                CandidateImage(urls: item.thumbnail).frame(width: 65, height: 98).clipShape(RoundedRectangle(cornerRadius: 8))
                                metadata(row, title: item.title).frame(maxWidth: .infinity, alignment: .leading)
                            }.detailCard()
                        }
                    }.buttonStyle(.plain).accessibilityLabel([item.title, localDate(row.text("release_date"), locale: locale), row.text("pages") + " " + preferences.text("Pages"), preferences.text(row.text("count_type"))].filter { !$0.isEmpty }.joined(separator: ", ")).accessibilityIdentifier("work-cover-\(row.id)")
                    .accessibilityHint(Text(row.workImages.isEmpty ? "Series cover used as fallback" : "Preview cover")).frame(width: width).contentShape(Rectangle())
                }
            }
        }.fullScreenCover(item: $gallery) { presentation in ImageViewer(items: presentation.items, selected: presentation.selectedID) }
    }
    private func metadata(_ row: DetailRecord, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).lineLimit(2, reservesSpace: true)
            Text(row.text("release_date").isEmpty ? " " : localDate(row.text("release_date"), locale: locale)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                if let pages = Int(row.text("pages")) { Text("\(pages) pages") } else { Text("Pages unknown") }
                Text(preferences.text(row.text("count_type")))
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(row.records("price").first.map { $0.text("value") + " " + $0.text("iso_code").uppercased() } ?? " ").font(.caption).foregroundStyle(.green).lineLimit(1)
        }
    }
}
