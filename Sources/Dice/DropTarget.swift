import AppKit
import SwiftUI
import DiceCore

enum DragTarget: String, Codable, CaseIterable, Identifiable {
    case off = "Off", bottomLeft = "Bottom left corner", bottomRight = "Bottom right corner"
    var id: String { rawValue }
}

/// Watches for file drags anywhere on screen and reveals a small drop target that opens the dragged files in Dice:
/// in the chosen corner when the pointer reaches it, or right under the pointer when it shakes.
@MainActor final class DragDropWatcher {
    var target: DragTarget = .off { didSet { if target == .off && !shake { hide() } } }
    var shake = false { didSet { if target == .off && !shake { hide() } } }
    var onDrop: ([URL]) -> Void = { _ in }
    var isAvailable: () -> Bool = { true }
    private var monitor: Any?
    private var downCount = 0
    private var fileDrag = false
    private var panel: NSPanel?
    private var view: DropTargetView?
    private var shaking = ShakeDetector()
    /// Shown under the pointer by a shake: it stays there until the drag ends, so the files can be dropped on it.
    private var pinned = false

    init() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; hide() }

    private func handle(_ type: NSEvent.EventType) {
        let drag = NSPasteboard(name: .drag)
        switch type {
        case .leftMouseDown: downCount = drag.changeCount; fileDrag = false; pinned = false; shaking.reset()
        case .leftMouseDragged:
            guard target != .off || shake, isAvailable(), !pinned else { return }
            if !fileDrag, drag.changeCount != downCount, drag.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { fileDrag = true }
            guard fileDrag else { return }
            let point = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return }
            if shake, shaking.shook(x: point.x, at: ProcessInfo.processInfo.systemUptime) { pinned = true; show(on: screen, at: point) }
            else if inZone(point, screen.frame) { show(on: screen) }
        case .leftMouseUp:
            fileDrag = false; pinned = false; shaking.reset()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.hide() }
        default: break
        }
    }
    private func inZone(_ p: NSPoint, _ f: NSRect) -> Bool {
        switch target {
        case .off: return false
        case .bottomLeft: return p.x < f.minX + 150 && p.y < f.minY + 150
        case .bottomRight: return p.x > f.maxX - 150 && p.y < f.minY + 150
        }
    }
    /// Shows the drop target in the chosen corner, or centred on `pointer` (kept on the screen) after a shake.
    private func show(on screen: NSScreen, at pointer: NSPoint? = nil) {
        if panel == nil {
            let content = DropTargetView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
            content.onDrop = { [weak self] urls in self?.hide(); self?.onDrop(urls) }
            let p = NSPanel(contentRect: content.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.contentView = content; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            // isFloatingPanel resets the level to .floating, below the Dock, so the level is set after it.
            p.isFloatingPanel = true; p.level = .statusBar; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p; view = content
        }
        guard let panel else { return }
        // The screen's own corner, not the visible frame, which stops above the Dock. The panel's level is above the
        // Dock, so it stays in view even where the Dock reaches the corner.
        let f = screen.frame, size = panel.frame.size
        let origin: NSPoint
        if let pointer {
            origin = NSPoint(x: min(max(pointer.x - size.width / 2, f.minX + 8), f.maxX - size.width - 8),
                             y: min(max(pointer.y - size.height / 2, f.minY + 8), f.maxY - size.height - 8))
        } else {
            switch target {
            case .bottomLeft, .off: origin = NSPoint(x: f.minX + 14, y: f.minY + 14)
            case .bottomRight: origin = NSPoint(x: f.maxX - size.width - 14, y: f.minY + 14)
            }
        }
        panel.setFrameOrigin(origin)
        if !panel.isVisible {
            panel.alphaValue = 0; panel.orderFrontRegardless()
            // The shadow follows the window's drawn, rounded shape; work it out again once the panel has drawn.
            DispatchQueue.main.async { panel.invalidateShadow() }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        }
    }
    private func hide() {
        guard let panel, panel.isVisible else { return }
        view?.highlight(false)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }, completionHandler: { [weak panel] in panel?.orderOut(nil) })
    }
}

final class DropTargetView: NSVisualEffectView {
    var onDrop: ([URL]) -> Void = { _ in }
    private let title = NSTextField(labelWithString: "Drop to open")
    private let subtitle = NSTextField(labelWithString: "in Dice")
    private let icon = NSImageView()
    private let tint = CAGradientLayer()
    private let dashes = CAShapeLayer()
    private static let radius: CGFloat = 30
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover; blendingMode = .behindWindow; state = .active; appearance = nil
        wantsLayer = true
        layer?.cornerRadius = Self.radius; layer?.cornerCurve = .continuous; layer?.masksToBounds = true
        layer?.borderWidth = 1; layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        tint.colors = DiceStyle.nsAurora.map { $0.withAlphaComponent(0.24).cgColor }
        tint.startPoint = CGPoint(x: 0, y: 1); tint.endPoint = CGPoint(x: 1, y: 0); tint.opacity = 0; layer?.addSublayer(tint)
        dashes.fillColor = nil; dashes.lineWidth = 1.5; dashes.lineDashPattern = [5, 5]; dashes.lineCap = .round
        dashes.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor; layer?.addSublayer(dashes)
        icon.isEditable = false; icon.unregisterDraggedTypes()
        icon.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 34, weight: .light)
        icon.contentTintColor = .labelColor
        title.font = .systemFont(ofSize: 14, weight: .semibold); title.textColor = .labelColor
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        let text = NSStackView(views: [title, subtitle]); text.orientation = .vertical; text.spacing = 1; text.alignment = .centerX
        let stack = NSStackView(views: [icon, text]); stack.orientation = .vertical; stack.spacing = 10; stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    /// Child views (the image view in particular) would otherwise take over the drag and refuse the drop.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func layout() {
        super.layout()
        tint.frame = bounds
        dashes.frame = bounds
        dashes.path = CGPath(roundedRect: bounds.insetBy(dx: 12, dy: 12), cornerWidth: Self.radius - 12, cornerHeight: Self.radius - 12, transform: nil)
        if maskImage?.size != bounds.size { maskImage = Self.roundedMask(bounds.size) }
    }
    /// A layer's corner radius doesn't clip a blur of what's behind the window, and the window's shadow follows that
    /// blur, so both stayed square at the corners. The mask gives the material, and with it the shadow, the same
    /// rounded shape as the border.
    private static func roundedMask(_ size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
            context.setFillColor(.black); context.fillPath()
            return true
        }
    }
    func highlight(_ on: Bool) {
        let accent = DiceStyle.nsAccent
        tint.opacity = on ? 1 : 0
        dashes.strokeColor = (on ? accent : NSColor.white.withAlphaComponent(0.35)).cgColor
        layer?.borderColor = (on ? accent.withAlphaComponent(0.8) : NSColor.white.withAlphaComponent(0.18)).cgColor
        icon.contentTintColor = on ? accent : .labelColor
        icon.image = NSImage(systemSymbolName: on ? "arrow.down.circle.fill" : "square.and.arrow.down", accessibilityDescription: nil)
        title.stringValue = on ? "Release to open" : "Drop to open"
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { highlight(true); return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlight(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        onDrop(urls); return true
    }
}
