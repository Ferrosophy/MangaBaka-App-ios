import Foundation
import SwiftData
import Observation
import Network

enum ReadingStatus: String, CaseIterable, Codable, Identifiable {
    case reading, paused, completed, planToRead = "plan_to_read", dropped, rereading, considering
    var id: String { rawValue }
    var title: String { switch self { case .reading: "Reading"; case .paused: "Paused"; case .completed: "Completed"; case .planToRead: "Plan to read"; case .dropped: "Dropped"; case .rereading: "Rereading"; case .considering: "Considering" } }
    var icon: String { switch self { case .reading: "book"; case .paused: "pause.circle"; case .completed: "checkmark.circle"; case .planToRead: "bookmark"; case .dropped: "xmark.circle"; case .rereading: "arrow.clockwise"; case .considering: "lightbulb" } }
}
struct LibraryEntry: Codable, Identifiable, Equatable {
    var id: String { seriesID }
    var remoteID: String
    var seriesID: String
    var title: String
    var localizedTitles: [String: String]
    var aliases: [String]
    var coverURL: URL?
    var totalChapters: Int?
    var totalVolumes: Int?
    var state: ReadingStatus
    var chapters: Int
    var volumes: Int
    var rereads: Int
    var rating: Int?
    var createdAt: Date
    var updatedAt: Date
    func displayTitle(_ locale: Locale) -> String { localizedTitles[locale.identifier.hasPrefix("zh") ? "zh" : "en"] ?? title }
    var percentage: Double? {
        if let n = totalChapters, n > 0 { return min(1, Double(chapters) / Double(n)) }
        if let n = totalVolumes, n > 0 { return min(1, Double(volumes) / Double(n)) }
        return nil
    }
    static func parse(_ row: [String: Any]) throws -> Self {
        guard let series = (row["Series"] ?? row["series"]) as? [String: Any], let card = HomeCard.parse(series, shelf: .trending), Int(card.id) != nil,
              let state = ReadingStatus(rawValue: HomeCard.string(row["state"])), !HomeCard.string(row["id"]).isEmpty else { throw AccountError.message("The server returned an incomplete library record. Cached data was preserved.") }
        func number(_ key: String) throws -> Int {
            guard let v = row[key], !(v is NSNull) else { return 0 }
            guard let n = Int(HomeCard.string(v)), n >= 0, n <= 10_000_000 else { throw AccountError.message("The server returned an invalid reading record.") }; return n
        }
        let rating = row["rating"] is NSNull || row["rating"] == nil ? nil : Int(HomeCard.string(row["rating"]))
        if let rating, !(0...100).contains(rating) { throw AccountError.message("The server returned an invalid rating.") }
        guard let created = Self.date(HomeCard.string(row["created_at"])), let updated = Self.date(HomeCard.string(row["updated_at"])) else { throw AccountError.message("The server returned an invalid record timestamp.") }
        return Self(remoteID: HomeCard.string(row["id"]), seriesID: card.id, title: card.title, localizedTitles: card.localizedTitles,
                    aliases: (series["titles"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }, coverURL: card.image,
                    totalChapters: Int(HomeCard.string(series["total_chapters"])), totalVolumes: Int(HomeCard.string(series["final_volume"])), state: state,
                    chapters: try number("progress_chapter"), volumes: try number("progress_volume"), rereads: try number("number_of_rereads"), rating: rating, createdAt: created, updatedAt: updated)
    }
    static func date(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    static func draft(series: DetailRecord, state: ReadingStatus) -> Self {
        let card = series.card
        return Self(remoteID: "", seriesID: series.id, title: card?.title ?? series.text("title"), localizedTitles: card?.localizedTitles ?? [:], aliases: [], coverURL: series.cover, totalChapters: Int(series.text("total_chapters")), totalVolumes: Int(series.text("final_volume")), state: state, chapters: 0, volumes: 0, rereads: 0, rating: nil, createdAt: Date(), updatedAt: Date())
    }
    var writeBody: [String: Any] { ["state": state.rawValue, "progress_chapter": chapters, "progress_volume": volumes, "number_of_rereads": rereads, "rating": rating.map { $0 as Any } ?? NSNull()] }
    func validateBackup() throws {
        guard Int(seriesID).map({ $0 > 0 }) == true, (0...10_000_000).contains(chapters), (0...10_000_000).contains(volumes), (0...10_000_000).contains(rereads), rating.map({ (0...100).contains($0) }) ?? true,
              !title.isEmpty, totalChapters.map({ $0 >= 0 }) ?? true, totalVolumes.map({ $0 >= 0 }) ?? true else { throw AccountError.message("The backup contains an invalid reading record.") }
    }
}
@Model final class LibraryCache {
    @Attribute(.unique) var owner: String
    var payload: Data
    var syncedAt: Date
    init(owner: String, payload: Data, syncedAt: Date) { self.owner = owner; self.payload = payload; self.syncedAt = syncedAt }
}
@MainActor @Observable final class LibraryRepository {
    let auth: AuthSession
    private let context: ModelContext
    var entries: [LibraryEntry] = []
    var syncing = false
    var writing = false
    var restoring = false
    var online = true
    var error: String?
    var lastSync: Date?
    var complete = false
    private var owner: String?
    private var accountGeneration: UUID?
    private var syncID = UUID()
    private let monitor = NWPathMonitor()
    var canWrite: Bool { auth.isAuthenticated && online && !syncing && !writing && !restoring && owner == auth.profile?.id && complete }
    init(auth: AuthSession, context: ModelContext) {
        self.auth = auth; self.context = context
        monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.online = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "mangabaka.network"))
    }
    deinit { monitor.cancel() }
    func activate() {
        let id = auth.profile?.id
        guard id != owner || accountGeneration != auth.generation else { return }
        accountGeneration = auth.generation; syncID = UUID(); syncing = false
        entries = []; lastSync = nil; complete = false; error = nil; owner = id
        guard let id else { return }
        do {
            let caches = try context.fetch(FetchDescriptor<LibraryCache>())
            if let cached = caches.first(where: { $0.owner == id }) { entries = try JSONDecoder().decode([LibraryEntry].self, from: cached.payload); lastSync = cached.syncedAt }
        } catch { self.error = "Unable to read the cached library. Refresh to try again." }
    }
    func clearForLogout() throws {
        guard !writing && !restoring else { throw AccountError.message("Wait for the current save to finish.") }
        let id = owner
        try auth.logout()
        owner = nil; syncID = UUID(); syncing = false; entries = []; complete = false; lastSync = nil
        for cached in try context.fetch(FetchDescriptor<LibraryCache>()) where cached.owner == id { context.delete(cached) }
        try context.save()
    }
    private func persist() throws {
        guard let owner, let lastSync else { return }
        let data = try JSONEncoder().encode(entries)
        if let row = try context.fetch(FetchDescriptor<LibraryCache>()).first(where: { $0.owner == owner }) { row.payload = data; row.syncedAt = lastSync }
        else { context.insert(LibraryCache(owner: owner, payload: data, syncedAt: lastSync)) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func sync() async {
        activate()
        guard auth.isAuthenticated, online, !syncing, !writing, !restoring else { return }
        let epoch = auth.generation, expected = owner
        let runID = UUID(); syncID = runID; syncing = true; error = nil
        defer { if syncID == runID { syncing = false } }
        do {
            let all = try await fetchAll(epoch: epoch)
            guard auth.generation == epoch, owner == expected else { return }
            let old = entries, oldDate = lastSync
            entries = all; lastSync = Date()
            do { try persist(); complete = true } catch { entries = old; lastSync = oldDate; throw error }
        } catch { if auth.generation == epoch { self.error = friendly(error) } }
    }
    private func fetchAll(epoch: UUID) async throws -> [LibraryEntry] {
        var all: [LibraryEntry] = [], seen = Set<String>()
        for page in 1...1000 {
            let data = try await auth.request(path: "my/library?page=\(page)&limit=100&sort_by=updated_at_desc")
            guard epoch == auth.generation else { throw AccountError.stale }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = root["data"] as? [[String: Any]] else { throw AccountError.message("Unable to read the cloud library. Cached data was preserved.") }
            for row in rows {
                let entry = try LibraryEntry.parse(row)
                guard seen.insert(entry.id).inserted else { throw AccountError.message("The cloud library changed during sync. Refresh to try again.") }
                all.append(entry)
            }
            if rows.count < 100 { return all }
        }
        throw AccountError.message("The library sync is incomplete. Cached data was preserved.")
    }
    func save(_ entry: LibraryEntry, create: Bool = false) async throws {
        guard canWrite else { throw AccountError.message("Connect and finish syncing before editing your library.") }
        writing = true; defer { writing = false }
        try await performSave(entry, create: create)
    }
    private func performSave(_ entry: LibraryEntry, create: Bool) async throws {
        try entry.validateBackup()
        let epoch = auth.generation
        do {
            // Existing records accept partial PUTs; create then populate all fields.
            if create { _ = try await auth.request(path: "my/library/\(entry.id)", method: "POST", body: ["state": entry.state.rawValue]) }
            _ = try await auth.request(path: "my/library/\(entry.id)", method: "PUT", body: entry.writeBody)
        } catch {
            // A timeout may follow a committed write. Read back before offering a retry.
            if let all = try? await fetchAll(epoch: epoch), auth.generation == epoch {
                entries = all; lastSync = Date(); try? persist()
                if let actual = all.first(where: { $0.id == entry.id }), actual.state == entry.state, actual.chapters == entry.chapters, actual.volumes == entry.volumes, actual.rereads == entry.rereads, actual.rating == entry.rating { return }
            }
            throw error
        }
        guard auth.generation == epoch else { throw AccountError.stale }
        var next = entry; next.updatedAt = Date()
        entries.removeAll { $0.id == entry.id }; entries.append(next)
        do { try persist() } catch { self.error = "Saved to cloud. Refresh to rebuild the local cache." }
    }
    func remove(_ entry: LibraryEntry) async throws {
        guard canWrite else { throw AccountError.message("Connect and finish syncing before editing your library.") }
        writing = true; defer { writing = false }
        let epoch = auth.generation
        _ = try await auth.request(path: "my/library/\(entry.id)", method: "DELETE")
        guard auth.generation == epoch else { throw AccountError.stale }
        entries.removeAll { $0.id == entry.id }
        do { try persist() } catch { self.error = "Saved to cloud. Refresh to rebuild the local cache." }
    }
    func restore(_ records: [LibraryEntry], overwrite: Set<String>) async -> [LibraryEntry] {
        guard canWrite else { error = "Connect and finish syncing before restoring a backup."; return records }
        restoring = true
        var failed: [LibraryEntry] = []
        for entry in records {
            let exists = entries.contains { $0.id == entry.id }
            if exists && !overwrite.contains(entry.id) { continue }
            do { try await performSave(entry, create: !exists) } catch { failed.append(entry) }
        }
        restoring = false
        await sync()
        return failed
    }
    func friendly(_ error: Error) -> String { (error as? AccountError)?.errorDescription ?? "Request failed. Check your connection and try again." }
}
struct LibraryStatistics {
    let entries: [LibraryEntry]
    var total: Int { entries.count }
    var chapters: Int { entries.reduce(0) { $0 + $1.chapters } }
    var volumes: Int { entries.reduce(0) { $0 + $1.volumes } }
    var rereads: Int { entries.reduce(0) { $0 + $1.rereads } }
    var completed: Int { entries.filter { $0.state == .completed }.count }
    var completion: Double { total == 0 ? 0 : Double(completed) / Double(total) * 100 }
    var finish: Double { let n = completed + entries.filter { $0.state == .dropped }.count; return n == 0 ? 0 : Double(completed) / Double(n) * 100 }
    var mean: Double? { let scores = entries.compactMap(\.rating); return scores.isEmpty ? nil : Double(scores.reduce(0,+)) / Double(scores.count) }
    var highest: LibraryEntry? { entries.filter { $0.rating != nil }.sorted { $0.rating == $1.rating ? $0.title < $1.title : ($0.rating ?? 0) > ($1.rating ?? 0) }.first }
    var mostReread: LibraryEntry? { entries.filter { $0.rereads > 0 }.sorted { $0.rereads == $1.rereads ? $0.title < $1.title : $0.rereads > $1.rereads }.first }
}
struct LibraryBackup: Codable {
    let version: Int
    let exportedAt: Date
    let accountName: String
    let entries: [LibraryEntry]
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 20_000_000 else { throw AccountError.message("The backup is too large.") }
        let backup = try JSONDecoder().decode(Self.self, from: data)
        guard backup.version == 1, backup.entries.count <= 10000, Set(backup.entries.map(\.id)).count == backup.entries.count else { throw AccountError.message("The backup format is unsupported or contains duplicate records.") }
        try backup.entries.forEach { try $0.validateBackup() }
        return backup
    }
}
