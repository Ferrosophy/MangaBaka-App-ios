import SwiftUI
import UniformTypeIdentifiers

struct LoginRequiredView: View {
    @Environment(AuthSession.self) private var auth
    var body: some View {
        ContentUnavailableView {
            Label("Sign in to MangaBaka", systemImage: "person.crop.circle")
        } description: { Text("Sign in to sync your library, reading progress and ratings.") } actions: {
            Button("Sign in") { Task { await auth.login() } }.buttonStyle(.borderedProminent).disabled(auth.signingIn)
            if auth.signingIn { ProgressView() }
            if let warning = auth.storageWarning { Text(LocalizedStringKey(warning)).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}
struct SyncBanner: View {
    @Environment(LibraryRepository.self) private var library
    @Environment(AuthSession.self) private var auth
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !library.online { Label("Offline — cached library is read-only", systemImage: "wifi.slash") }
            if library.syncing { HStack { ProgressView(); Text("Syncing library…") } }
            if !library.complete && library.lastSync != nil { Text("Showing cached statistics until sync completes.") }
            if let date = library.lastSync { HStack { Text("Last synced"); Text(date, style: .relative) }.font(.caption).foregroundStyle(.secondary) }
            if let error = library.error { Text(LocalizedStringKey(error)).foregroundStyle(.orange); Button("Retry") { Task { await library.sync() } }.disabled(library.syncing || library.writing || library.restoring) }
        }.font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct LibraryView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(LibraryRepository.self) private var library
    @Environment(\.locale) private var locale
    @State private var status: ReadingStatus = .reading
    @State private var query = ""
    @AppStorage("library-grid") private var grid = true
    @AppStorage("library-sort") private var sort = "updated"
    @State private var backup = false
    private var rows: [LibraryEntry] {
        library.entries.filter { $0.state == status && (query.isEmpty || ([$0.title] + Array($0.localizedTitles.values) + $0.aliases).contains { $0.localizedCaseInsensitiveContains(query) }) }.sorted {
            switch sort {
            case "title": return $0.displayTitle(locale).localizedStandardCompare($1.displayTitle(locale)) == .orderedAscending
            case "rating": return $0.rating == $1.rating ? $0.title < $1.title : ($0.rating ?? -1) > ($1.rating ?? -1)
            case "created": return $0.createdAt > $1.createdAt
            default: return $0.updatedAt > $1.updatedAt
            }
        }
    }
    var body: some View {
        Group {
            if !auth.isAuthenticated { LoginRequiredView() }
            else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(ReadingStatus.allCases) { s in
                            Button { status = s } label: {
                                HStack { Text(LocalizedStringKey(s.title)); Text("\(library.entries.filter { $0.state == s }.count)") }.padding(.horizontal, 12).padding(.vertical, 10).background(status == s ? Color.green.opacity(0.22) : .clear, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(status == s ? .isSelected : [])
                        } }.padding(.horizontal)
                    }
                    ScrollView {
                        VStack(spacing: 16) {
                            SyncBanner()
                            if rows.isEmpty {
                                ContentUnavailableView(query.isEmpty ? "No books in this category" : "No results found", systemImage: "books.vertical", description: Text(query.isEmpty ? "Add a series from its detail page to start your library." : "Try another title or clear your search."))
                            } else if grid {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .top)], alignment: .leading, spacing: 20) { ForEach(rows) { entry in NavigationLink { SeriesDetailView(id: entry.id) } label: { LibraryTile(entry: entry) }.buttonStyle(.plain) } }
                            } else {
                                LazyVStack { ForEach(rows) { entry in NavigationLink { SeriesDetailView(id: entry.id) } label: { HStack { LibraryTile(entry: entry, compact: true); Spacer(); Image(systemName: "chevron.right") } }.buttonStyle(.plain) } }
                            }
                        }.padding()
                    }.refreshable { await library.sync() }
                }.searchable(text: $query, prompt: "Search your library")
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if auth.isAuthenticated {
                    Menu {
                        Picker("Sort by", selection: $sort) { Text("Recently updated").tag("updated"); Text("Recently added").tag("created"); Text("Title").tag("title"); Text("Personal rating").tag("rating") }
                        Toggle("Grid layout", isOn: $grid)
                        Button("Backup and restore", systemImage: "arrow.up.arrow.down") { backup = true }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("Library options")
                }
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $backup) { NavigationStack { BackupView() } }
        .task { await library.sync() }
    }
}
struct LibraryTile: View {
    let entry: LibraryEntry
    var compact = false
    @Environment(\.locale) private var locale
    var body: some View {
        if compact {
            HStack { CandidateImage(urls: entry.coverURL.map { [$0] } ?? []).frame(width: 55, height: 82).clipShape(RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading) { Text(entry.displayTitle(locale)).font(.headline); Text(LocalizedStringKey(entry.state.title)).font(.caption).foregroundStyle(.secondary); Text("\(entry.chapters) chapters · \(entry.volumes) volumes").font(.caption) } }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                CandidateImage(urls: entry.coverURL.map { [$0] } ?? []).aspectRatio(2/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(entry.displayTitle(locale)).font(.subheadline.bold()).lineLimit(2)
                if let value = entry.percentage { ProgressView(value: value).accessibilityLabel("Reading progress") }
            }.accessibilityElement(children: .combine)
        }
    }
}
struct SeriesLibraryPanel: View {
    let series: DetailRecord
    @Environment(AuthSession.self) private var auth
    @Environment(LibraryRepository.self) private var library
    @State private var editing: LibraryEditKind?
    @State private var confirmCompleted = false
    @State private var confirmDelete = false
    @State private var failure: String?
    private var entry: LibraryEntry? { library.entries.first { $0.id == series.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !auth.isAuthenticated {
                Button("Sign in to add to library", systemImage: "bookmark.badge.plus") { Task { await auth.login() } }.disabled(auth.signingIn)
            } else if let entry {
                HStack { Text("Library").font(.headline); Spacer(); if let p = entry.percentage { Text(p, format: .percent.precision(.fractionLength(0))) } else { Text("Progress unknown") } }
                Menu { ForEach(ReadingStatus.allCases) { state in Button { if state == .completed && entry.state != .completed { confirmCompleted = true } else { changeState(state, entry: entry) } } label: { Label(LocalizedStringKey(state.title), systemImage: state.icon) } } } label: { HStack { Label(LocalizedStringKey(entry.state.title), systemImage: entry.state.icon); Spacer(); Image(systemName: "chevron.down") }.padding().background(.quaternary, in: Capsule()) }.disabled(!library.canWrite)
                progressRow("Chapters", current: entry.chapters, total: entry.totalChapters, kind: .chapters)
                progressRow("Volumes", current: entry.volumes, total: entry.totalVolumes, kind: .volumes)
                Divider()
                Button { editing = .rating } label: { HStack { Text("Personal rating"); Spacer(); if let rating = entry.rating { Text("\(rating) / 100") } else { Text("Not rated") }; Image(systemName: "pencil") } }.disabled(!library.canWrite)
                Button { editing = .rereads } label: { HStack { Text("Rereads"); Spacer(); Text("\(entry.rereads)"); Image(systemName: "pencil") } }.disabled(!library.canWrite)
                Button("Remove from library", systemImage: "trash", role: .destructive) { confirmDelete = true }.disabled(!library.canWrite)
            } else {
                Menu { ForEach(ReadingStatus.allCases) { state in Button(LocalizedStringKey(state.title)) {
                    let draft = LibraryEntry.draft(series: series, state: state)
                    if state == .completed { confirmCompleted = true } else { save(draft, create: true) }
                } } } label: { Label("Add to library", systemImage: "bookmark.badge.plus") }.disabled(!library.canWrite)
            }
            if auth.isAuthenticated && !library.canWrite {
                if library.writing { ProgressView() }
                else if !library.online { Text("Offline — cached library is read-only").font(.caption).foregroundStyle(.secondary) }
                else if !library.complete { Button("Sync before editing") { Task { await library.sync() } }.disabled(library.syncing) }
            }
        }.padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
        .sheet(item: $editing) { kind in if let entry { LibraryEditSheet(entry: entry, kind: kind) } }
        .confirmationDialog("Mark as completed?", isPresented: $confirmCompleted, titleVisibility: .visible) {
            Button("Complete and fill known progress") { var next = entry ?? LibraryEntry.draft(series: series, state: .completed); next.state = .completed; if let n = next.totalChapters, n > 0 { next.chapters = n }; if let n = next.totalVolumes, n > 0 { next.volumes = n }; save(next, create: entry == nil) }
        } message: { Text("Known chapter and volume totals will be filled. Unknown totals will keep your current progress.") }
        .confirmationDialog("Remove from library?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let entry { Task { do { try await library.remove(entry) } catch { failure = library.friendly(error) } } } }
        } message: { Text("This deletes the cloud reading record, including progress, rating and rereads.") }
        .alert("Unable to save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK") { failure = nil } } message: { Text(LocalizedStringKey(failure ?? "")) }
    }
    private func changeState(_ state: ReadingStatus, entry: LibraryEntry) { var next = entry; next.state = state; save(next) }
    private func save(_ entry: LibraryEntry, create: Bool = false) { Task { do { try await library.save(entry, create: create) } catch { failure = library.friendly(error) } } }
    private func progressRow(_ title: String, current: Int, total: Int?, kind: LibraryEditKind) -> some View {
        VStack {
            Button { editing = kind } label: { HStack { Text(LocalizedStringKey(title)); Spacer(); Text("\(current) / \(total.map(String.init) ?? "—")"); Image(systemName: "plus.circle") } }.disabled(!library.canWrite)
            if let total, total > 0 { ProgressView(value: min(1, Double(current) / Double(total))) }
        }
    }
}
enum LibraryEditKind: String, Identifiable { case chapters = "Update chapters", volumes = "Update volumes", rating = "Set your rating", rereads = "Update rereads"; var id: String { rawValue } }
struct LibraryEditSheet: View {
    let entry: LibraryEntry
    let kind: LibraryEditKind
    @Environment(LibraryRepository.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var number: String
    @State private var failure: String?
    @State private var saving = false
    init(entry: LibraryEntry, kind: LibraryEditKind) {
        self.entry = entry; self.kind = kind
        let value: Int = switch kind { case .chapters: entry.chapters; case .volumes: entry.volumes; case .rating: entry.rating ?? 0; case .rereads: entry.rereads }
        _number = State(initialValue: String(value))
    }
    private var total: Int? { switch kind { case .chapters: entry.totalChapters; case .volumes: entry.totalVolumes; case .rating: 100; case .rereads: nil } }
    private var value: Int? { Int(number) }
    private var valid: Bool { guard let value, value >= 0, value <= 10_000_000 else { return false }; return total.map { $0 <= 0 || value <= $0 } ?? true }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let total { LabeledContent("Total", value: "\(total)") }
                    HStack {
                        Button { number = String(max(0, (value ?? 0) - 1)) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Decrease")
                        TextField("Value", text: $number).keyboardType(.numberPad).multilineTextAlignment(.center).accessibilityIdentifier("reading-value")
                        Button { number = String(min(total.flatMap { $0 > 0 ? $0 : nil } ?? Int.max - 1, min(value ?? 0, 9_999_999) + 1)) } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless).accessibilityLabel("Increase")
                    }
                    if kind == .rating {
                        Slider(value: Binding(get: { Double(value ?? 0) }, set: { number = String(Int($0.rounded())) }), in: 0...100, step: 1).accessibilityLabel("Personal rating")
                        Button("Clear rating", role: .destructive) { commit(clear: true) }.disabled(!library.canWrite || saving)
                    }
                    if !valid { Text("Enter a non-negative whole number within the known total.").foregroundStyle(.orange) }
                }
                if let failure { Section { Text(LocalizedStringKey(failure)).foregroundStyle(.orange) } }
                if saving { ProgressView() }
            }.navigationTitle(LocalizedStringKey(kind.rawValue)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { commit() }.disabled(!valid || !library.canWrite || saving) }
                }.interactiveDismissDisabled(saving)
        }.presentationDetents([.medium, .large])
    }
    private func commit(clear: Bool = false) {
        var next = entry
        switch kind { case .chapters: next.chapters = value ?? 0; case .volumes: next.volumes = value ?? 0; case .rereads: next.rereads = value ?? 0; case .rating: next.rating = clear ? nil : value }
        saving = true
        Task { do { try await library.save(next); dismiss() } catch { failure = library.friendly(error) }; saving = false }
    }
}
