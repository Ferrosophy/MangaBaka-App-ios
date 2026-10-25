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
    var totalChapters: Double?
    var totalVolumes: Double?
    var state: ReadingStatus
    var chapters: Double
    var volumes: Double
    var rereads: Int
    var rating: Double?
    var note: String? = nil
    var isPrivate: Bool? = nil
    var readLink: String? = nil
    var priority: Int? = nil
    var startDate: String? = nil
    var finishDate: String? = nil
    var contentRating: String? = nil
    var nativeTitle: String? = nil
    var createdAt: Date?
    var updatedAt: Date?
    func displayTitle(_ locale: Locale) -> String { localizedTitles[locale.identifier.hasPrefix("zh") ? "zh" : "en"] ?? title }
    var percentage: Double? {
        if let n = totalChapters, n > 0 { return min(1, Double(chapters) / Double(n)) }
        if let n = totalVolumes, n > 0 { return min(1, Double(volumes) / Double(n)) }
        return nil
    }
    static func parse(_ source: [String: Any]) throws -> Self {
        // v2 separates tracking (entry) and metadata (series); accept old backups too.
        var row = source["entry"] as? [String: Any] ?? source
        if let series = source["series"] as? [String: Any] { row["Series"] = series }
        guard let series = (row["Series"] ?? row["series"]) as? [String: Any], let card = HomeCard.parse(series, shelf: .trending), Int(card.id) != nil,
              let state = ReadingStatus(rawValue: HomeCard.string(row["state"])), !HomeCard.string(row["id"]).isEmpty else { throw AccountError.message("The server returned an incomplete library record. Cached data was preserved.") }
        func number(_ key: String) throws -> Double {
            guard let v = row[key], !(v is NSNull) else { return 0 }
            guard let n = Double(HomeCard.string(v)), n.isFinite, n >= 0, n <= (key == "number_of_rereads" ? 1000 : 10000) else { throw AccountError.message("The server returned an invalid reading record.") }; return n
        }
        let rawRating = row["rating"] is NSNull || row["rating"] == nil ? nil : Double(HomeCard.string(row["rating"]))
        if row["rating"] != nil && !(row["rating"] is NSNull) && rawRating == nil { throw AccountError.message("The server returned an invalid rating.") }
        let rating = rawRating == 0 ? nil : rawRating
        if let rating, !(0...100).contains(rating) { throw AccountError.message("The server returned an invalid rating.") }
        let created = Self.date(HomeCard.string(row["created_at"])), updated = Self.date(HomeCard.string(row["updated_at"]))
        let rereads = try number("number_of_rereads")
        guard rereads.rounded() == rereads else { throw AccountError.message("The server returned an invalid reading record.") }
        return Self(remoteID: HomeCard.string(row["id"]), seriesID: card.id, title: card.title, localizedTitles: card.localizedTitles,
                    aliases: (series["titles"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }, coverURL: card.image,
                    totalChapters: Double(HomeCard.string(series["total_chapters"])), totalVolumes: Double(HomeCard.string(series["final_volume"])), state: state,
                    chapters: try number("progress_chapter"), volumes: try number("progress_volume"), rereads: Int(rereads), rating: rating, note: row["note"] as? String, isPrivate: row["is_private"] as? Bool, readLink: row["read_link"] as? String, priority: (row["priority"] as? NSNumber)?.intValue, startDate: row["start_date"] as? String, finishDate: row["finish_date"] as? String, contentRating: card.contentRating, nativeTitle: card.nativeTitle, createdAt: created, updatedAt: updated)
    }
    static func date(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    static func draft(series: DetailRecord, state: ReadingStatus) -> Self {
        let card = series.card
        return Self(remoteID: "", seriesID: series.id, title: card?.title ?? series.text("title"), localizedTitles: card?.localizedTitles ?? [:], aliases: [], coverURL: series.cover, totalChapters: Double(series.text("total_chapters")), totalVolumes: Double(series.text("final_volume")), state: state, chapters: 0, volumes: 0, rereads: 0, rating: nil, contentRating: card?.contentRating, nativeTitle: card?.nativeTitle, createdAt: Date(), updatedAt: Date())
    }
    var writeBody: [String: Any] {
        var body: [String: Any] = ["state": state.rawValue, "progress_chapter": chapters, "progress_volume": volumes, "number_of_rereads": rereads, "rating": rating.map { $0 as Any } ?? NSNull(), "note": note.map { $0 as Any } ?? NSNull()]
        // Preserve website-only tracking fields when restoring a new record.
        if let isPrivate { body["is_private"] = isPrivate }
        if let readLink { body["read_link"] = readLink }
        if let priority { body["priority"] = priority }
        if let startDate { body["start_date"] = startDate }
        if let finishDate { body["finish_date"] = finishDate }
        return body
    }
    static func validRecordedDate(_ value: String) -> Bool {
        if Self.date(value) != nil { return true }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.calendar = Calendar(identifier: .gregorian); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        return format.date(from: value).map { format.string(from: $0) == value } ?? false
    }
    func validateBackup() throws {
        guard Int(seriesID).map({ $0 > 0 }) == true, (0...10000).contains(chapters), (0...10000).contains(volumes), (0...1000).contains(rereads), rating.map({ (0...100).contains($0) }) ?? true,
              !title.isEmpty, totalChapters.map({ $0 >= 0 }) ?? true, totalVolumes.map({ $0 >= 0 }) ?? true, priority.map({ (10...30).contains($0) }) ?? true, startDate.map(Self.validRecordedDate) ?? true, finishDate.map(Self.validRecordedDate) ?? true, readLink.map({ URL(string: $0)?.scheme != nil }) ?? true else { throw AccountError.message("The backup contains an invalid reading record.") }
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
            try Task.checkCancellation()
            let data = try await auth.request(path: "my/library?page=\(page)&limit=100&sort_by=updated_at_desc&schema=full", version: 2)
            guard epoch == auth.generation else { throw AccountError.stale }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = root["data"] as? [[String: Any]] else { throw AccountError.message("Unable to read the cloud library. Cached data was preserved.") }
            for row in rows {
                let entry = try LibraryEntry.parse(row)
                guard seen.insert(entry.id).inserted else { throw AccountError.message("The cloud library changed during sync. Refresh to try again.") }
                all.append(entry)
            }
            if let pagination = root["pagination"] as? [String: Any], pagination.keys.contains("next") {
                if pagination["next"] is NSNull { return all }
                guard pagination["next"] is String, !rows.isEmpty else { throw AccountError.message("The library sync is incomplete. Cached data was preserved.") }
            } else if rows.count < 100 { return all }
        }
        throw AccountError.message("The library sync is incomplete. Cached data was preserved.")
    }
    func save(_ entry: LibraryEntry, create: Bool = false) async throws {
        guard canWrite else { throw AccountError.message("Connect and finish syncing before editing your library.") }
        writing = true; defer { writing = false }
        try await performSave(entry, create: create)
    }
    private func performSave(_ original: LibraryEntry, create: Bool) async throws {
        var entry = original; if entry.rating == 0 { entry.rating = nil }
        try entry.validateBackup()
        let epoch = auth.generation
        do {
            let body = Self.changedFields(entry, previous: create ? nil : entries.first { $0.id == entry.id })
            if !body.isEmpty { _ = try await auth.request(path: "my/library/\(entry.id)", method: create ? "POST" : "PATCH", body: body) }
        } catch {
            // A timeout may follow a committed write. Read back before offering a retry.
            if let all = try? await fetchAll(epoch: epoch), auth.generation == epoch {
                entries = all; lastSync = Date(); try? persist()
                if let actual = all.first(where: { $0.id == entry.id }), actual.state == entry.state, actual.chapters == entry.chapters, actual.volumes == entry.volumes, actual.rereads == entry.rereads, actual.rating == entry.rating { return }
            }
            throw error
        }
        guard auth.generation == epoch else { throw AccountError.stale }
        var next = entry; next.updatedAt = Date(); if next.rating == 0 { next.rating = nil }
        entries.removeAll { $0.id == entry.id }; entries.append(next)
        do { try persist() } catch { self.error = "Saved to cloud. Refresh to rebuild the local cache." }
    }
    static func changedFields(_ next: LibraryEntry, previous: LibraryEntry?) -> [String: Any] {
        guard let previous else { return next.writeBody }
        var body: [String: Any] = [:]
        if next.state != previous.state { body["state"] = next.state.rawValue }
        if next.chapters != previous.chapters { body["progress_chapter"] = next.chapters }
        if next.volumes != previous.volumes { body["progress_volume"] = next.volumes }
        if next.rereads != previous.rereads { body["number_of_rereads"] = next.rereads }
        if next.rating != previous.rating { body["rating"] = next.rating.map { $0 as Any } ?? NSNull() }
        if next.note != previous.note { body["note"] = next.note.map { $0 as Any } ?? NSNull() }
        if let value = next.isPrivate, next.isPrivate != previous.isPrivate { body["is_private"] = value }
        if let value = next.readLink, next.readLink != previous.readLink { body["read_link"] = value }
        if let value = next.priority, next.priority != previous.priority { body["priority"] = value }
        if let value = next.startDate, next.startDate != previous.startDate { body["start_date"] = value }
        if let value = next.finishDate, next.finishDate != previous.finishDate { body["finish_date"] = value }
        return body
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
        let epoch = auth.generation, account = owner
        for (index, entry) in records.enumerated() {
            guard auth.generation == epoch, owner == account, auth.isAuthenticated else {
                failed.append(contentsOf: records[index...]); break
            }
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
    var chapters: Double { entries.reduce(0) { $0 + $1.chapters } }
    var volumes: Double { entries.reduce(0) { $0 + $1.volumes } }
    var rereads: Int { entries.reduce(0) { $0 + $1.rereads } }
    var completed: Int { entries.filter { $0.state == .completed }.count }
    var completion: Double { total == 0 ? 0 : Double(completed) / Double(total) * 100 }
    var finish: Double { let n = completed + entries.filter { $0.state == .dropped }.count; return n == 0 ? 0 : Double(completed) / Double(n) * 100 }
    var mean: Double? { let scores = entries.compactMap(\.rating).filter { $0 > 0 }; return scores.isEmpty ? nil : scores.reduce(0,+) / Double(scores.count) }
    var highest: LibraryEntry? { entries.filter { ($0.rating ?? 0) > 0 }.sorted { $0.rating == $1.rating ? $0.title < $1.title : ($0.rating ?? 0) > ($1.rating ?? 0) }.first }
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

enum ReadingNumber {
    static func string(_ value: Double) -> String { value.rounded() == value ? String(format: "%.0f", value) : String(value) }
}
