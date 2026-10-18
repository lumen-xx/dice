import SwiftUI
import AppKit
import Combine
import ServiceManagement

@main struct DiceApp {
    static func main() {
        // AppKit owns the run loop; don't hold a Swift main-actor job across app.run().
        MainActor.assumeIsolated { run() }
    }
    @MainActor private static func run() {
        let app = NSApplication.shared
        let delegate = DiceDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        let menu = NSMenu(); let root = NSMenuItem(); let applicationMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(DiceDelegate.showSettings(_:)), keyEquivalent: ",")
        settings.target = delegate; applicationMenu.addItem(settings)
        let save = NSMenuItem(title: "Save Copies As…", action: #selector(DiceDelegate.saveCopies(_:)), keyEquivalent: "s")
        save.keyEquivalentModifierMask = [.command, .shift]; save.target = delegate
        applicationMenu.addItem(save); applicationMenu.addItem(.separator())
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(DiceDelegate.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = delegate; applicationMenu.addItem(updates)
        let previews = NSMenuItem(title: "Include Preview Releases", action: #selector(DiceDelegate.togglePreviewUpdates(_:)), keyEquivalent: "")
        previews.target = delegate; previews.state = delegate.updates.includePreviews ? .on : .off
        applicationMenu.addItem(previews); applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Dice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = applicationMenu; menu.addItem(root)
        // Without an Edit menu, Command-C/V/X/A/Z never reach text fields. Paste outside a text field adds images (DiceDelegate.paste).
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; menu.addItem(edit)
        app.mainMenu = menu
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
final class DiceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func miniaturize(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
    override func toggleFullScreen(_ sender: Any?) {}
}
@MainActor final class DiceDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = DiceModel()
    lazy var updates = DiceUpdates(model: model)
    var window: NSWindow?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    var dragWatcherCreated = false
    lazy var dragWatcher: DragDropWatcher = {
        let watcher = DragDropWatcher()
        watcher.onDrop = { [weak self] urls in self?.dropOnMenuBar(urls) }
        watcher.isAvailable = { [weak self] in !(self?.model.busy ?? true) && !(self?.model.importing ?? true) }
        return watcher
    }()
    var preferenceObserver: AnyCancellable?
    var isDevelopmentBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "DiceDevelopmentBuild") as? Bool == true }
    func applyPreferences(_ p: AppPreferences) {
        window?.level = p.stayOnTop ? .floating : .normal
        if p.dragTarget != .off || p.shakeForDropTarget || dragWatcherCreated {
            dragWatcherCreated = true; dragWatcher.target = p.dragTarget; dragWatcher.shake = p.shakeForDropTarget
        }
        if p.showInMenuBar, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "die.face.5", accessibilityDescription: "Dice")
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open Dice", action: #selector(openFromMenu(_:)), keyEquivalent: ""); open.target = self; menu.addItem(open)
            let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ""); settings.target = self; menu.addItem(settings)
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Dice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            statusMenu = menu; statusItem = item
            item.button?.target = self; item.button?.action = #selector(statusItemClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else if !p.showInMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item); statusItem = nil
        }
        if let button = statusItem?.button {
            let existing = button.subviews.compactMap { $0 as? StatusDropView }.first
            if p.menuBarDrop, existing == nil {
                let drop = StatusDropView(frame: button.bounds); drop.autoresizingMask = [.width, .height]
                drop.onDrop = { [weak self] urls in self?.dropOnMenuBar(urls) }
                button.addSubview(drop)
            } else if !p.menuBarDrop { existing?.removeFromSuperview() }
        }
        guard !isDevelopmentBuild else { return }
        let service = SMAppService.mainApp
        if p.startAtLogin, service.status != .enabled { try? service.register() }
        else if !p.startAtLogin, service.status == .enabled { try? service.unregister() }
    }
    /// Left click opens Dice right away; right click (or control-click) shows the menu.
    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { showWindow(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            guard let item = statusItem, let menu = statusMenu else { return }
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
        } else { showWindow() }
    }
    func dropOnMenuBar(_ urls: [URL]) {
        guard !model.busy && !model.importing else { showWindow(); model.alert = "Finish the current images before opening another selection."; return }
        model.startWhenReady = model.preferences.dropStartsImmediately
        openImages(urls)
    }
    @objc func openFromMenu(_ sender: Any?) { showWindow() }
    /// Close the window once a run finishes; quit unless the menu bar item keeps Dice available.
    func finishRun() {
        guard model.preferences.closeWhenDone else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            window?.close()
            if !model.preferences.showInMenuBar { NSApp.terminate(nil) }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onFinished = { [weak self] in self?.finishRun() }
        applyPreferences(model.preferences)
        preferenceObserver = model.$preferences.removeDuplicates().sink { [weak self] p in self?.applyPreferences(p) }
        if Bundle.main.object(forInfoDictionaryKey: "DiceDevelopmentBuild") as? Bool != true { NSApp.servicesProvider = self; NSUpdateDynamicServices() }; updates.start(); showWindow() }
    @objc func showSettings(_ sender: Any?) { showWindow(); model.settingsPresented = true }
    @objc func saveCopies(_ sender: Any?) { model.save() }
    /// Reached when no text field takes the paste: pasted files or image data join the batch.
    @objc func paste(_ sender: Any?) {
        guard !model.busy && !model.importing else { model.alert = "Finish the current images before adding more."; return }
        showWindow(); model.paste()
    }
    @objc func checkForUpdates(_ sender: Any?) { showWindow(); updates.check(sender) }
    @objc func togglePreviewUpdates(_ sender: NSMenuItem) { updates.includePreviews.toggle(); sender.state = updates.includePreviews ? .on : .off }
    // Finder launches should reveal Dice's drop surface, never the default document picker.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool { showWindow(); return true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    /// 620 × 460, or `--size <width>x<height>` for screenshots.
    private static var launchSize: NSSize {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--size"), index + 1 < arguments.count else { return NSSize(width: 620, height: 460) }
        let parts = arguments[index + 1].split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : NSSize(width: 620, height: 460)
    }
    func showWindow() {
        if window == nil {
            let w = DiceWindow(contentRect: NSRect(origin: .zero, size: Self.launchSize), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            w.title = "Dice"; w.hasShadow = true
            w.isReleasedWhenClosed = false; w.isOpaque = false; w.backgroundColor = .clear
            w.isMovableByWindowBackground = true; w.delegate = self
            w.collectionBehavior.insert(.fullScreenNone); w.level = model.preferences.stayOnTop ? .floating : .normal
            let effect = NSVisualEffectView(); effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
            effect.wantsLayer = true; effect.layer?.cornerRadius = DiceStyle.cornerRadius; effect.layer?.masksToBounds = true
            let hosting = DiceHostingView(rootView: DiceView(model: model, close: { [weak w] in w?.close() }, checkUpdates: { [weak self] in self?.updates.check(nil) })); hosting.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(hosting)
            NSLayoutConstraint.activate([hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor), hosting.topAnchor.constraint(equalTo: effect.topAnchor), hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)])
            w.contentView = effect; w.center(); window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func application(_ sender: NSApplication, open urls: [URL]) { openImages(urls) }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { openImages(filenames.map { URL(fileURLWithPath: $0) }); sender.reply(toOpenOrPrint: .success) }
    @objc func editWithDice(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty, let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        }
        guard !urls.isEmpty else { error.pointee = "Select an image or PDF to edit with Dice."; return }
        guard !model.busy && !model.importing else {
            showWindow(); error.pointee = "Finish the current images before opening another selection."; return
        }
        openImages(urls)
    }
    /// macOS delivers a mixed Finder selection (say photos and an SVG) as several open events, one per type,
    /// moments apart. Events within a quarter of a second are gathered into one selection, so a later event doesn't
    /// replace the files an earlier one brought.
    private var pendingOpen: [URL] = []
    private var pendingOpenFlush: DispatchWorkItem?
    func openImages(_ urls: [URL]) {
        guard pendingOpenFlush != nil || !(model.busy || model.importing) else { showWindow(); model.alert = "Finish the current images before opening another selection."; return }
        pendingOpen += urls
        pendingOpenFlush?.cancel()
        let flush = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let urls = self.pendingOpen; self.pendingOpen = []; self.pendingOpenFlush = nil
            guard !self.model.busy && !self.model.importing else { self.showWindow(); self.model.alert = "Finish the current images before opening another selection."; return }
            self.model.clear(); self.showWindow(); self.model.add(urls)
        }
        pendingOpenFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: flush)
    }
    func windowWillClose(_ notification: Notification) { window = nil; model.settingsPresented = false; model.closeSession(); NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.cleanup() }
}

/// Sits over the menu bar button to accept dropped files while passing clicks through to the button.
final class StatusDropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    override func rightMouseUp(with event: NSEvent) { nextResponder?.rightMouseUp(with: event) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        onDrop(urls); return true
    }
}
