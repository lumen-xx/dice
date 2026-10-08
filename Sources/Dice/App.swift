import SwiftUI
import AppKit

@main struct DiceApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = DiceDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        let menu = NSMenu(); let root = NSMenuItem(); let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Dice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = applicationMenu; menu.addItem(root); app.mainMenu = menu
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class DiceDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = DiceModel()
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 390), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Dice"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false; w.isOpaque = false; w.backgroundColor = .clear
            w.isMovableByWindowBackground = true; w.delegate = self
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(type)?.isHidden = true }
            let effect = NSVisualEffectView(); effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
            effect.wantsLayer = true; effect.layer?.cornerRadius = 14; effect.layer?.masksToBounds = true
            let hosting = NSHostingView(rootView: DiceView(model: model)); hosting.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(hosting)
            NSLayoutConstraint.activate([hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor), hosting.topAnchor.constraint(equalTo: effect.topAnchor), hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)])
            w.contentView = effect; w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func application(_ sender: NSApplication, open urls: [URL]) { openImages(urls) }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { openImages(filenames.map { URL(fileURLWithPath: $0) }); sender.reply(toOpenOrPrint: .success) }
    func openImages(_ urls: [URL]) {
        guard !model.busy && !model.importing else { showWindow(); model.alert = "Finish the current images before opening another selection."; return }
        model.clear(); showWindow(); model.add(urls)
    }
    func windowWillClose(_ notification: Notification) { window = nil; if !model.busy && !model.importing { model.clear() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.cleanup() }
}
