import AppKit
import SwiftUI

/// Command-scroll and pinch anywhere over the window zoom into the photo around the pointer. Zoomed in, plain
/// scrolling moves around it. Points are relative to this view's centre, with y going down, as SwiftUI offsets do.
struct ZoomCatcher: NSViewRepresentable {
    var zoomed: Bool
    let onZoom: (_ factor: CGFloat, _ at: CGPoint, _ size: CGSize) -> Void
    let onPan: (_ by: CGSize, _ size: CGSize) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = PassThrough(); context.coordinator.view = view; context.coordinator.start(); update(context.coordinator); return view
    }
    func updateNSView(_ view: NSView, context: Context) { update(context.coordinator) }
    private func update(_ coordinator: Coordinator) { coordinator.zoomed = zoomed; coordinator.onZoom = onZoom; coordinator.onPan = onPan }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    final class PassThrough: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
    final class Coordinator {
        weak var view: NSView?
        var zoomed = false
        var onZoom: (CGFloat, CGPoint, CGSize) -> Void = { _, _, _ in }
        var onPan: (CGSize, CGSize) -> Void = { _, _ in }
        private var monitor: Any?
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        /// Whether the event was used.
        private func handle(_ event: NSEvent) -> Bool {
            guard let view, let window = view.window, event.window === window else { return false }
            let p = view.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: p.x - view.bounds.midX, y: view.isFlipped ? p.y - view.bounds.midY : view.bounds.midY - p.y)
            if event.type == .magnify { onZoom(1 + event.magnification, point, view.bounds.size); return true }
            if event.modifierFlags.contains(.command) {
                // A wheel's clicks come in lines, sped up when it spins; each zooms by at most a quarter.
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : max(-0.22, min(0.22, event.scrollingDeltaY * 0.1))
                if delta != 0 { onZoom(exp(delta), point, view.bounds.size) }
                return true
            }
            guard zoomed else { return false }
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            onPan(CGSize(width: event.scrollingDeltaX * step, height: event.scrollingDeltaY * step), view.bounds.size)
            return true
        }
    }
}

/// Where a zoomed photo may sit: `zoom` times its unzoomed size, moved by `pan` from where it was. Larger than the
/// window along a side, it covers the window along that side; smaller, it stays where it was.
enum PhotoZoom {
    static let most: CGFloat = 16
    /// The photo's size before zooming: fitted inside `frame`, or filling it (and cropped) when it fills the window.
    static func content(_ image: CGSize, in frame: CGSize, fill: Bool) -> CGSize {
        guard fill, image.width > 0, image.height > 0 else { return frame }
        let scale = max(frame.width / image.width, frame.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
    /// `frame` is where the unzoomed photo sits in the `area` it can be seen in.
    static func clamp(_ pan: CGSize, zoom: CGFloat, content: CGSize, frame: CGRect, area: CGSize) -> CGSize {
        func side(_ pan: CGFloat, _ size: CGFloat, _ middle: CGFloat, _ area: CGFloat) -> CGFloat {
            let zoomed = size * zoom
            guard zoomed > area else { return 0 }
            return min(zoomed / 2 - middle, max(area - zoomed / 2 - middle, pan))
        }
        return CGSize(width: side(pan.width, content.width, frame.midX, area.width), height: side(pan.height, content.height, frame.midY, area.height))
    }
}
