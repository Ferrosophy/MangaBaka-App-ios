import SwiftUI

/// The image is an overlay inside a proposed viewport; bitmap dimensions never size a cell.
struct CoverViewport: View {
    let image: UIImage?
    var loading = false
    var mode: ContentMode = .fill
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: mode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if loading { ProgressView() }
                else { Image(systemName: "book.closed").font(.title2).foregroundStyle(.secondary) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}

/// Ends the native control on every completion path, including cancellation and timeout.
@MainActor final class RefreshHandle {
    weak var scroll: UIScrollView?
    func finish() {
        guard let scroll else { return }
        scroll.refreshControl?.endRefreshing()
        DispatchQueue.main.async { [weak scroll] in
            guard let scroll, !scroll.isDragging, !scroll.isDecelerating else { return }
            scroll.layoutIfNeeded()
            let top = -scroll.adjustedContentInset.top
            if scroll.contentOffset.y < top - 1 { scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: true) }
        }
    }
}
private struct RefreshProbe: UIViewRepresentable {
    let handle: RefreshHandle
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            var ancestor: UIView? = view.superview
            func find(_ node: UIView) -> UIScrollView? {
                if let s = node as? UIScrollView, s.refreshControl != nil { return s }
                for child in node.subviews { if let s = find(child) { return s } }
                return nil
            }
            while let node = ancestor {
                if let scroll = find(node) { handle.scroll = scroll; return }
                ancestor = node.superview
            }
        }
    }
}
@MainActor private struct SafeRefresh: ViewModifier {
    let action: @MainActor () async -> Void
    @State private var handle = RefreshHandle()
    func body(content: Content) -> some View {
        content.background(RefreshProbe(handle: handle).allowsHitTesting(false))
            .refreshable {
                defer { Task { @MainActor in handle.finish() } }
                await RefreshDeadline.run(action: action)
            }
    }
}
enum RefreshDeadline {
    @MainActor static func run(seconds: Double = 60, action: @escaping @MainActor () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await action() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)) }
            await group.next(); group.cancelAll()
        }
    }
}
extension View {
    @MainActor func safeRefreshable(_ action: @escaping @MainActor () async -> Void) -> some View { modifier(SafeRefresh(action: action)) }
}
