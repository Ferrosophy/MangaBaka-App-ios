import SwiftUI

struct SourceScoresView: View {
    let series: DetailRecord
    let links: [DetailRecord]
    let openURL: (URL) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(Preferences.self) private var preferences
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading, spacing: 8) {
            if let score = series.score {
                HStack(spacing: 6) { Image(systemName: "star.fill").foregroundStyle(.yellow).frame(width: iconSize, height: iconSize); Text(score, format: .number.precision(.fractionLength(1))).bold().monospacedDigit().lineLimit(1).minimumScaleFactor(0.65) }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(preferences.text("Community rating")) \(String(format: "%.1f", score))")
            }
            ForEach(series.sourceScores, id: \.name) { source in
                let url = source.url ?? links.first(where: { $0.text("name").lowercased().contains(source.name.lowercased()) }).flatMap { safeURL($0.text("url")) }
                Button { if let url { openURL(url) } } label: {
                    HStack(spacing: 6) {
                        if UIImage(named: "source-" + source.name) != nil { Image("source-" + source.name).resizable().scaledToFit().frame(width: iconSize, height: iconSize).background(["anilist", "kitsu", "anime_news_network"].contains(source.name) ? Color(red: 0.08, green: 0.13, blue: 0.20) : .clear, in: RoundedRectangle(cornerRadius: 4)) }
                        else { Image(systemName: "globe").frame(width: iconSize, height: iconSize) }
                        Text(source.score, format: .number.precision(.fractionLength(0))).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(url == nil)
                    .accessibilityLabel("\(DetailRecord.sourceName(source.name)) \(Int(source.score))")
                    .accessibilityIdentifier("source-score-\(source.name)")
            }
        }.accessibilityIdentifier("source-scores")
    }
}
