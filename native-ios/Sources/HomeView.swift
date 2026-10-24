import SwiftUI

struct HomeView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.locale) private var locale
    @State private var model = HomeModel()
    @State private var web: WebPage?
    @State private var loaded = false
    private let types = [("", "Any"), ("manga", "Manga"), ("manhwa", "Manhwa"), ("manhua", "Manhua"), ("novel", "Novel")]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                ForEach(Shelf.allCases) { shelf in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(LocalizedStringKey(shelf.title)).font(.title2.bold())
                            Spacer()
                            // The web discover page is the verified public discovery entry.
                            if shelf == .trending || shelf == .upcoming {
                                Button { web = WebPage(url: discoveryURL(shelf)) } label: { Image(systemName: "arrow.up.right").frame(width: 44, height: 44) }
                                    .accessibilityLabel(Text("View on MangaBaka"))
                            }
                        }.padding(.horizontal, 20)
                        if shelf == .trending { filters }
                        shelfContent(shelf)
                    }
                }
                Text("Data provided by MangaBaka").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
            }.padding(.vertical, 12).padding(.bottom, 24)
        }
        .navigationTitle("Home")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel(Text("Settings")) } }
        .refreshable { await model.refresh() }
        .task { if !loaded { loaded = true; await model.refresh() } }
        .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
    }
    private var filters: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(types, id: \.0) { type in
                        Button {
                            model.type = type.0
                            Task { await model.load(.trending) }
                        } label: {
                            Text(LocalizedStringKey(type.1)).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                                .background(model.type == type.0 ? Color.green.opacity(0.22) : Color.secondary.opacity(0.1), in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(model.type == type.0 ? .isSelected : [])
                    }
                }.padding(.horizontal, 20)
            }
            Picker("Time period", selection: $model.days) { Text("7 days").tag(7); Text("30 days").tag(30) }
                .pickerStyle(.segmented).padding(.horizontal, 20)
                .onChange(of: model.days) { Task { await model.load(.trending) } }
        }
    }
    @ViewBuilder private func shelfContent(_ shelf: Shelf) -> some View {
        let state = model.states[shelf] ?? HomeModel.State()
        if state.loading && state.cards.isEmpty {
            HStack(spacing: 12) { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 16).fill(.quaternary).frame(width: 140, height: shelf == .publishers ? 150 : 230) } }
                .padding(.horizontal, 20).accessibilityLabel(Text("Loading"))
        } else if state.cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(state.failed ? "Unable to load this section" : "Nothing here yet")).foregroundStyle(.secondary)
                if state.failed { Button("Retry") { Task { await model.load(shelf) } }.frame(minHeight: 44) }
            }.padding(.horizontal, 20)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(state.cards) { card in cardView(card, shelf: shelf) }
                }.padding(.horizontal, 20)
            }.opacity(state.loading ? 0.5 : 1)
            if state.failed { Button("Unable to refresh. Retry") { Task { await model.load(shelf) } }.padding(.horizontal, 20) }
        }
    }
    private func cardView(_ card: HomeCard, shelf: Shelf) -> some View {
        Button { if let url = card.link { web = WebPage(url: url) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverImage(url: card.image).frame(width: shelf == .publishers ? 52 : 140, height: shelf == .publishers ? 52 : 210).clipShape(RoundedRectangle(cornerRadius: 14))
                if let date = card.date {
                    Text(releaseDate(date)).font(.caption.weight(.semibold)).foregroundStyle(.green)
                }
                if !card.volume.isEmpty { Text("Volume \(card.volume)").font(.caption).foregroundStyle(.green) }
                Text(card.displayTitle(locale: locale)).font(.subheadline.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if let count = card.count { Text("\(count) series").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(width: 140, alignment: .leading)
            .padding(shelf == .publishers ? 14 : 0)
            .background(shelf == .publishers ? Color.secondary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).disabled(card.link == nil)
    }
    private func releaseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }
    private func discoveryURL(_ shelf: Shelf) -> URL {
        var c = URLComponents(string: "https://mangabaka.org/discover")!
        if shelf == .trending { c.queryItems = [URLQueryItem(name: "sort_by", value: model.days == 30 ? "trending_30d" : "trending_7d"), URLQueryItem(name: "type", value: model.type)] }
        return c.url!
    }
}
