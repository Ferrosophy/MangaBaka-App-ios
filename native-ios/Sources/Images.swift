import SwiftUI
import CryptoKit

actor ImageCache {
    static let shared = ImageCache()
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CoverImages")
    private var generation = 0
    func data(for url: URL) async throws -> Data {
        let token = generation
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent(name)
        if let data = try? Data(contentsOf: file), UIImage(data: data) != nil { return data }
        try? FileManager.default.removeItem(at: file)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), UIImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
        if token == generation {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return data
    }
    func size() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    func clear() { generation += 1; try? FileManager.default.removeItem(at: folder); URLCache.shared.removeAllCachedResponses() }
}
struct CoverImage: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.coverRating) private var rating
    let url: URL?
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary) }
        }
        .clipped().blur(radius: preferences.blurredRatings.contains(rating ?? "") ? 18 : 0).accessibilityHidden(true)
        .task(id: url) {
            image = nil
            if let url, let data = try? await ImageCache.shared.data(for: url), !Task.isCancelled { image = UIImage(data: data) }
        }
    }
}
