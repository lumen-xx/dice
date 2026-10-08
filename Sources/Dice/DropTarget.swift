import AppKit

enum DragTarget: String, Codable, CaseIterable, Identifiable {
    case off = "Off", notch = "Top center (notch)"
    var id: String { rawValue }
}

/// Watches for file drags anywhere on screen and, when the pointer reaches the chosen edge,
/// reveals a small drop target that opens the dragged files in Dice.
@MainActor final class DragDropWatcher {
    var target: DragTarget = .off { didSet { if target == .off { hide() } } }
    var onDrop: ([URL]) -> Void = { _ in }
    var isAvailable: () -> Bool = { true }
    private var monitor: Any?
    private var downCount = 0
    private var fileDrag = false
    private var panel: NSPanel?
    private var view: DropTargetView?

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
        case .leftMouseDown: downCount = drag.changeCount; fileDrag = false
        case .leftMouseDragged:
            guard target != .off, isAvailable() else { return }
            if !fileDrag, drag.changeCount != downCount, drag.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { fileDrag = true }
            guard fileDrag else { return }
            let point = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }), inZone(point, screen.frame) { show(on: screen) }
        case .leftMouseUp:
            fileDrag = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.hide() }
        default: break
        }
    }
    private func inZone(_ p: NSPoint, _ f: NSRect) -> Bool {
        switch target {
        case .off: return false
        case .notch: return abs(p.x - f.midX) < 170 && p.y > f.maxY - 44
        }
    }
    private func show(on screen: NSScreen) {
        if panel == nil {
            let content = DropTargetView(frame: NSRect(x: 0, y: 0, width: 230, height: 60))
            content.onDrop = { [weak self] urls in self?.hide(); self?.onDrop(urls) }
            let p = NSPanel(contentRect: content.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.contentView = content; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .statusBar; p.isFloatingPanel = true; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p; view = content
        }
        guard let panel else { return }
        let f = screen.frame, v = screen.visibleFrame, size = panel.frame.size
        let origin: NSPoint
        switch target {
        case .notch, .off: origin = NSPoint(x: f.midX - size.width / 2, y: v.maxY - size.height - 6)
        case .topRight: origin = NSPoint(x: f.maxX - size.width - 14, y: v.maxY - size.height - 6)
        case .bottomRight: origin = NSPoint(x: f.maxX - size.width - 14, y: v.minY + 14)
        }
        panel.setFrameOrigin(origin)
        if !panel.isVisible {
            panel.alphaValue = 0; panel.orderFrontRegardless()
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
    private let label = NSTextField(labelWithString: "Drop to open in Dice")
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow; blendingMode = .behindWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 18; layer?.masksToBounds = true; layer?.borderWidth = 1; layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let icon = NSImageView(image: NSImage(systemSymbolName: "die.face.5", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13, weight: .medium); label.textColor = .labelColor
        let stack = NSStackView(views: [icon, label]); stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    func highlight(_ on: Bool) {
        layer?.borderColor = (on ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.12)).cgColor
        layer?.borderWidth = on ? 2 : 1
        label.stringValue = on ? "Release to open" : "Drop to open in Dice"
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { highlight(true); return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlight(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        onDrop(urls); return true
    }
}
