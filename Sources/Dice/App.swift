import SwiftUI
import AppKit

@main struct DiceApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = DiceDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        let menu = NSMenu(); let root = NSMenuItem(); let applicationMenu = NSMenu()
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(DiceDelegate.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = delegate; applicationMenu.addItem(updates)
        let previews = NSMenuItem(title: "Include Preview Releases", action: #selector(DiceDelegate.togglePreviewUpdates(_:)), keyEquivalent: "")
        previews.target = delegate; previews.state = delegate.updates.includePreviews ? .on : .off
        applicationMenu.addItem(previews); applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Dice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = applicationMenu; menu.addItem(root); app.mainMenu = menu
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
    func applicationDidFinishLaunching(_ notification: Notification) { updates.start(); showWindow() }
    @objc func checkForUpdates(_ sender: Any?) { showWindow(); updates.check(sender) }
    @objc func togglePreviewUpdates(_ sender: NSMenuItem) { updates.includePreviews.toggle(); sender.state = updates.includePreviews ? .on : .off }
    // Finder launches should reveal Dice's drop surface, never the default document picker.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool { showWindow(); return true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func showWindow() {
        if window == nil {
            let w = DiceWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            w.title = "Dice"; w.hasShadow = true
            w.isReleasedWhenClosed = false; w.isOpaque = false; w.backgroundColor = .clear
            w.isMovableByWindowBackground = true; w.delegate = self
            w.collectionBehavior.insert(.fullScreenNone)
            let effect = NSVisualEffectView(); effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
            effect.wantsLayer = true; effect.layer?.cornerRadius = DiceStyle.cornerRadius; effect.layer?.masksToBounds = true
            let hosting = NSHostingView(rootView: DiceView(model: model, close: { [weak w] in w?.close() })); hosting.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(hosting)
            NSLayoutConstraint.activate([hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor), hosting.topAnchor.constraint(equalTo: effect.topAnchor), hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)])
            w.contentView = effect; w.center(); window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func application(_ sender: NSApplication, open urls: [URL]) { openImages(urls) }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { openImages(filenames.map { URL(fileURLWithPath: $0) }); sender.reply(toOpenOrPrint: .success) }
    func openImages(_ urls: [URL]) {
        guard !model.busy && !model.importing else { showWindow(); model.alert = "Finish the current images before opening another selection."; return }
        model.clear(); showWindow(); model.add(urls)
    }
    func windowWillClose(_ notification: Notification) { window = nil; model.closeSession(); NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.cleanup() }
}
