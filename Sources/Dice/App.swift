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
    var statusItem: NSStatusItem?
    var preferenceObserver: AnyCancellable?
    var isDevelopmentBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "DiceDevelopmentBuild") as? Bool == true }
    func applyPreferences(_ p: AppPreferences) {
        window?.level = p.stayOnTop ? .floating : .normal
        if p.showInMenuBar, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "die.face.5", accessibilityDescription: "Dice")
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open Dice", action: #selector(openFromMenu(_:)), keyEquivalent: ""); open.target = self; menu.addItem(open)
            let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ""); settings.target = self; menu.addItem(settings)
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Dice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            item.menu = menu; statusItem = item
        } else if !p.showInMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item); statusItem = nil
        }
        guard !isDevelopmentBuild else { return }
        let service = SMAppService.mainApp
        if p.startAtLogin, service.status != .enabled { try? service.register() }
        else if !p.startAtLogin, service.status == .enabled { try? service.unregister() }
    }
    @objc func openFromMenu(_ sender: Any?) { showWindow() }
    /// Close the window once a run finishes; quit unless the menu bar item keeps Dice available.
    func finishRun() {
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
    func openImages(_ urls: [URL]) {
        guard !model.busy && !model.importing else { showWindow(); model.alert = "Finish the current images before opening another selection."; return }
        model.clear(); showWindow(); model.add(urls)
    }
    func windowWillClose(_ notification: Notification) { window = nil; model.closeSession(); NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.cleanup() }
}
