import SwiftUI

struct SeriesInfoView: View {
    let series: DetailRecord
    let links: [DetailRecord]
    let tagPaths: [String: String]
    let openURL: (URL) -> Void
    @Environment(\.locale) private var locale
    @Environment(Preferences.self) private var preferences
    @State private var expanded = false
    @State private var allTags = false
    @State private var copied = false
    private var descriptionText: String {
        series.text("description").replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br />", with: "\n").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !series.sourceScores.isEmpty {
                FlowLayout(spacing: 12) {
                    if let score = series.score { Text("★ \(score, specifier: "%.1f")").bold() }
                    ForEach(series.sourceScores, id: \.name) { source in
                        let url = source.url ?? links.first(where: { $0.text("name").lowercased().contains(source.name.lowercased()) }).flatMap { safeURL($0.text("url")) }
                        Button { if let url { openURL(url) } } label: { Text("\(source.name)  \(source.score, specifier: "%.0f")").font(.subheadline) }.disabled(url == nil).frame(minHeight: 44)
                    }
                }
            }
            if !descriptionText.isEmpty {
                heading("Description")
                Text((try? AttributedString(markdown: descriptionText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(descriptionText)).lineSpacing(6).lineLimit(expanded ? nil : 8).textSelection(.enabled)
                HStack {
                    Button(LocalizedStringKey(expanded ? "Show less" : "Show more")) { expanded.toggle() }.frame(minHeight: 44)
                    Spacer()
                    Button { UIPasteboard.general.string = descriptionText; copied = true } label: { Label(LocalizedStringKey(copied ? "Copied" : "Copy description"), systemImage: "doc.on.doc") }.frame(minHeight: 44)
                }
            }
            let genres = names("genres_v2", fallback: "genres")
            if !genres.isEmpty { heading("Genres"); FlowLayout { ForEach(genres, id: \.self) { chip($0) } } }
            infoCard
            let anime = series.object("anime")
            if !anime.values.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    heading("Anime adaptation")
                    infoRow("Anime start", anime.text("start"))
                    infoRow("Anime stop", anime.text("end").isEmpty ? anime.text("stop") : anime.text("end"))
                }.detailCard()
            }
            let groups = tagGroups
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    heading("Tags")
                    ForEach(Array((allTags ? groups : Array(groups.prefix(2))).enumerated()), id: \.offset) { index, group in
                        TagGroup(group: group)
                    }
                    if groups.count > 2 { Button(LocalizedStringKey(allTags ? "Show fewer tags" : "Show all tags")) { allTags.toggle() }.frame(minHeight: 44) }
                }.detailCard()
            }
            if !links.isEmpty {
                heading("Links")
                ForEach(links) { link in
                    if let url = safeURL(link.text("url")) {
                        Button { openURL(url) } label: {
                            HStack { Image(systemName: "link"); Text(link.text("name_display").isEmpty ? (link.text("name").isEmpty ? url.host ?? "" : link.text("name")) : link.text("name_display")); Spacer(); Text(link.text("language").uppercased()).font(.caption) }.padding(14).background(.thinMaterial, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Information")
            infoRow("Type", preferences.text(series.text("type")))
            infoRow("Status", preferences.text(series.text("status")))
            let dates = series.object("published")
            let start = dates.text("start_date").isEmpty ? dates.text("from") : dates.text("start_date")
            let end = dates.text("end_date").isEmpty ? dates.text("to") : dates.text("end_date")
            infoRow("Published", [start, end].filter { !$0.isEmpty }.map { localDate($0, locale: locale) }.joined(separator: " – "))
            infoRow("Chapters", series.text("total_chapters"))
            infoRow("Volumes", series.text("final_volume"))
            infoRow("Authors", series.names("authors"))
            infoRow("Artists", series.names("artists"))
            let publishers = series.records("publishers")
            if !publishers.isEmpty {
                heading("Publishers")
                ForEach(publishers) { publisher in
                    let name = publisher.text("name")
                    let url = safeURL(publisher.text("canonical_url")) ?? safeURL("https://mangabaka.org/publisher/\(publisher.text("id"))/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")
                    Button { if let url { openURL(url) } } label: { VStack(alignment: .leading) { Text(name); Text([publisher.text("language").uppercased(), preferences.text(publisher.text("type"))].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain).frame(minHeight: 44)
                }
                Divider()
            }
            infoRow("Content rating", preferences.text(series.text("content_rating")))
            HStack { infoRow("MangaBaka ID", series.id); Spacer(); Button { UIPasteboard.general.string = series.id } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel(Text("Copy ID")).frame(width: 44, height: 44) }
        }.detailCard()
    }
    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { heading(label); Text(value.isEmpty ? preferences.text("Unknown") : value).textSelection(.enabled); Divider() }
    }
    private func heading(_ key: String) -> some View { Text(LocalizedStringKey(key)).font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase) }
    private func chip(_ text: String) -> some View { Text(text).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8).background(Color.secondary.opacity(0.1), in: Capsule()) }
    private func names(_ key: String, fallback: String) -> [String] {
        let values = series.records(key).map { $0.text("name") }.filter { !$0.isEmpty }
        return Array(Set(values.isEmpty ? (series.values[fallback] as? [String] ?? []) : values)).sorted()
    }
    private var tagGroups: [ResolvedTagGroup] {
        let rows = series.records("tags_v2")
        let raw = rows.isEmpty ? (series.values["tags"] as? [String] ?? []) : rows.map { $0.text("name") }
        var paths = tagPaths
        for row in rows where !row.text("name_path").isEmpty { paths[row.text("name").lowercased()] = row.text("name_path") }
        return ResolvedTagGroup.resolve(names: raw, paths: paths)
    }
}
func safeURL(_ raw: String) -> URL? { guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }; return url }
extension View {
    func detailCard() -> some View { self.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 24)) }
}
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(width: proposal.width ?? 320, subviews: subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += height + spacing; height = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; height = max(height, size.height)
        }
        return (CGSize(width: width, height: y + height), points)
    }
}

struct TagGroup: View {
    let group: ResolvedTagGroup
    @State private var expanded = true
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.subgroups.keys.sorted(), id: \.self) { subtitle in
                    if !subtitle.isEmpty { Text(subtitle).font(.subheadline.bold()).foregroundStyle(.secondary) }
                    FlowLayout { ForEach(group.subgroups[subtitle] ?? [], id: \.self) { tag in Text(tag).font(.subheadline).padding(8).background(Color.secondary.opacity(0.1), in: Capsule()) } }
                }
            }.padding(.top, 8)
        } label: { Text(group.title).font(.headline) }
    }
}
