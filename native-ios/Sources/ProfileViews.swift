import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(LibraryRepository.self) private var library
    @State private var confirmLogout = false
    @State private var failure: String?
    private var stats: LibraryStatistics { LibraryStatistics(entries: library.entries) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !auth.isAuthenticated { LoginRequiredView().frame(minHeight: 350) }
                else {
                    HStack(spacing: 16) {
                        AsyncImage(url: auth.profile?.avatar) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }.frame(width: 64, height: 64).clipShape(Circle()).accessibilityHidden(true)
                        Text(auth.profile?.name ?? "MangaBaka").font(.title2.bold())
                    }
                    SyncBanner()
                    HStack { Text("At a glance").font(.title2.bold()); Spacer(); NavigationLink("Full statistics") { StatisticsView() } }
                    StatisticsGrid(items: [("Total series", "\(stats.total)", "books.vertical"), ("Chapters read", "\(stats.chapters)", "text.book.closed"), ("Volumes read", "\(stats.volumes)", "book.closed"), ("Mean score", stats.mean.map { String(format: "%.1f", $0) } ?? "—", "star")])
                    Text("Library snapshot").font(.title2.bold())
                    snapshot("Recently changed", rows: library.entries.sorted { $0.updatedAt > $1.updatedAt })
                    snapshot("Recently added", rows: library.entries.sorted { $0.createdAt > $1.createdAt })
                    NavigationLink("Backup and restore") { BackupView() }
                    Button("Sign out", role: .destructive) { confirmLogout = true }.disabled(library.writing || library.restoring || auth.signingIn)
                }
            }.padding()
        }.navigationTitle("Profile")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") } }
            .refreshable { await library.sync() }
            .task { await library.sync() }
            .confirmationDialog("Sign out?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { do { try library.clearForLogout() } catch { failure = library.friendly(error) } }
            } message: { Text("This removes the account and its cached library from this device. Your cloud library is kept.") }
            .alert("Unable to sign out", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK") { failure = nil } } message: { Text(LocalizedStringKey(failure ?? "")) }
    }
    private func snapshot(_ title: String, rows: [LibraryEntry]) -> some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey(title)).font(.headline)
            if rows.isEmpty { Text("Your library is empty.").foregroundStyle(.secondary) }
            else { ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 14) { ForEach(Array(rows.prefix(10))) { entry in NavigationLink { SeriesDetailView(id: entry.id) } label: { LibraryTile(entry: entry).frame(width: 120) }.buttonStyle(.plain) } } } }
        }
    }
}
struct StatisticsGrid: View {
    let items: [(String, String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(items.indices, id: \.self) { i in VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) { Text(items[i].1).font(.largeTitle.bold()).minimumScaleFactor(0.5); Spacer(); Image(systemName: items[i].2).foregroundStyle(.secondary) }
                Text(LocalizedStringKey(items[i].0)).font(.caption.bold()).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20)) }
        }
    }
}
struct StatisticsView: View {
    @Environment(LibraryRepository.self) private var library
    @Environment(AuthSession.self) private var auth
    @Environment(\.locale) private var locale
    var body: some View {
        Group {
            if !auth.isAuthenticated { LoginRequiredView() }
            else { ScrollView {
                let s = LibraryStatistics(entries: library.entries)
                VStack(alignment: .leading, spacing: 24) {
                    SyncBanner()
                    Text("Reading overview").font(.title2.bold())
                    StatisticsGrid(items: [("Total series", "\(s.total)", "books.vertical"), ("Chapters read", "\(s.chapters)", "text.book.closed"), ("Volumes read", "\(s.volumes)", "book.closed"), ("Completion", String(format: "%.1f%%", s.completion), "checkmark.circle"), ("Total rereads", "\(s.rereads)", "arrow.clockwise"), ("Mean score", s.mean.map { String(format: "%.1f", $0) } ?? "—", "star"), ("Finish rate", String(format: "%.1f%%", s.finish), "flag")])
                    if s.mean == nil { Text("No ratings yet").foregroundStyle(.secondary) }
                    Text("Completion is completed series divided by all series. Finish rate is completed divided by completed plus dropped.").font(.footnote).foregroundStyle(.secondary)
                    if s.highest != nil || s.mostReread != nil { Text("Standout picks").font(.title2.bold()) }
                    if let entry = s.highest { pick("Highest rated", entry: entry, value: "\(entry.rating ?? 0) / 100") }
                    if let entry = s.mostReread { pick("Most reread", entry: entry, value: "\(entry.rereads)") }
                }.padding()
            } }
        }.navigationTitle("Statistics")
    }
    private func pick(_ title: String, entry: LibraryEntry, value: String) -> some View {
        NavigationLink { SeriesDetailView(id: entry.id) } label: { VStack(alignment: .leading, spacing: 12) { Text(LocalizedStringKey(title)).foregroundStyle(.secondary); Text(entry.displayTitle(locale)).font(.headline); Text(value) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain)
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }; self.data = data }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct BackupView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(LibraryRepository.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var document = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: LibraryBackup?
    @State private var overwrite = Set<String>()
    @State private var failed: [LibraryEntry] = []
    @State private var message: String?
    @State private var confirm = false
    @State private var running = false
    var body: some View {
        Form {
            if !auth.isAuthenticated { LoginRequiredView() }
            else {
                Section("Account") { Text(auth.profile?.name ?? ""); Text("Restoring writes to the currently signed-in cloud account.").font(.footnote).foregroundStyle(.secondary) }
                Section {
                    Button("Export JSON backup") {
                        do { document = BackupDocument(data: try JSONEncoder().encode(LibraryBackup(version: 1, exportedAt: Date(), accountName: auth.profile?.name ?? "", entries: library.entries))); exporting = true } catch { message = "Unable to create the backup." }
                    }.disabled(!library.complete || library.syncing || running)
                    Button("Import JSON backup") { importing = true }.disabled(!library.canWrite || running)
                }
                if let backup {
                    Section("Restore preview") {
                        LabeledContent("Source account", value: backup.accountName)
                        LabeledContent("New series", value: "\(backup.entries.filter { e in !library.entries.contains { $0.id == e.id } }.count)")
                        Text("Existing cloud records are kept unless you select them below. Cloud-only records are never removed.").font(.footnote)
                        ForEach(backup.entries.filter { e in library.entries.contains { $0.id == e.id } }) { e in
                            Toggle(e.displayTitle(locale), isOn: Binding(get: { overwrite.contains(e.id) }, set: { if $0 { overwrite.insert(e.id) } else { overwrite.remove(e.id) } }))
                        }
                        Button("Restore to cloud") { confirm = true }.disabled(!library.canWrite || running)
                    }
                }
                if !failed.isEmpty { Section { Text("Some records could not be restored."); Text("\(failed.count)"); Button("Retry failed records") { restore(failed) }.disabled(!library.canWrite || running) } }
                if running { ProgressView("Restoring…") }
                if let message { Section { Text(LocalizedStringKey(message)) } }
            }
        }.navigationTitle("Backup and restore")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(running) } }
            .interactiveDismissDisabled(running)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "MangaBaka-library-backup") { result in if case .failure = result { message = "Unable to export the backup." } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20_000_000 else { throw AccountError.message("The backup is too large.") }
                    let next = try LibraryBackup.decode(Data(contentsOf: url)); backup = next; overwrite = []; failed = []; message = nil
                } catch { message = (error as? AccountError)?.errorDescription ?? "Unable to read this backup. No records were changed." }
            }
            .confirmationDialog("Restore to this cloud account?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Restore to cloud") { if let backup { restore(backup.entries) } }
            } message: { Text(auth.profile?.name ?? "") }
    }
    private func restore(_ records: [LibraryEntry]) {
        running = true
        Task { failed = await library.restore(records, overwrite: overwrite); message = failed.isEmpty ? "Restore completed." : "Some records could not be restored."; running = false }
    }
}
