import SwiftUI
import ImageIO

struct GalleryItem: Identifiable {
    let id: String
    let urls: [URL]
    let title: String
    var thumbnail: [URL] = []
}
struct ImageViewer: View {
    let items: [GalleryItem]
    @State var selected: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TabView(selection: $selected) {
                ForEach(items) { item in ZoomImage(urls: item.urls, active: abs((items.firstIndex(where: { $0.id == selected }) ?? 0) - (items.firstIndex(where: { $0.id == item.id }) ?? 0)) <= 1).tag(item.id).accessibilityLabel(item.title) }
            }.tabViewStyle(.page).background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .principal) { Text(items.first(where: { $0.id == selected })?.title ?? "").lineLimit(1).foregroundStyle(.white) }
                ToolbarItem(placement: .topBarTrailing) { if let url = items.first(where: { $0.id == selected })?.urls.first { ShareLink(item: url) } }
            }
        }.preferredColorScheme(.dark)
    }
}
struct ZoomImage: View {
    let urls: [URL]
    var active = true
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var previous: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var savedOffset: CGSize = .zero
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale).offset(offset)
                        .gesture(MagnificationGesture().onChanged { scale = min(5, max(1, previous * $0)) }.onEnded { _ in previous = scale; if scale == 1 { offset = .zero; savedOffset = .zero } })
                        .simultaneousGesture(DragGesture().onChanged { if scale > 1 { offset = CGSize(width: savedOffset.width + $0.translation.width, height: savedOffset.height + $0.translation.height) } }.onEnded { _ in savedOffset = offset })
                        .onTapGesture(count: 2) { scale = scale == 1 ? 2 : 1; previous = scale; offset = .zero; savedOffset = .zero }
                        .accessibilityLabel(Text("Cover image")).accessibilityIdentifier("gallery-loaded-image")
                } else if failed { Button("Retry") { retry += 1 } }
                else { ProgressView().tint(.white) }
            }.clipped()
        }.task(id: String(retry) + String(active)) {
            image = nil
            guard active else { return }
            failed = false
            for url in urls { if let data = try? await ImageCache.shared.data(for: url), let source = CGImageSourceCreateWithData(data as CFData, nil), let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 3072, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), !Task.isCancelled { image = UIImage(cgImage: cgImage); return } }
            failed = true
        }
    }
}
struct CandidateImage: View {
    let urls: [URL]
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed || urls.isEmpty { Image(systemName: "book.closed").foregroundStyle(.secondary) }
            else { ProgressView() }
        }.clipped()
        .task(id: urls.map(\.absoluteString).joined() + String(retry)) {
            image = nil; failed = false
            for url in urls { if let data = try? await ImageCache.shared.data(for: url), let decoded = UIImage(data: data), !Task.isCancelled { image = decoded; return } }
            failed = true
        }
    }
}
