import AppKit
import Sparkle
import Combine

@MainActor final class DiceUpdates: NSObject, SPUUpdaterDelegate {
    private let model: DiceModel
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var pendingInstall: (() -> Void)?
    private var preferencesObservation: AnyCancellable?
    private var started = false
    private var sessionObservation: AnyCancellable?
    private var windowObservation: NSObjectProtocol?
    var includePreviews: Bool {
        get { UserDefaults.standard.object(forKey: "dice.previewUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dice.previewUpdates") }
    }

    init(model: DiceModel) {
        self.model = model
        super.init()
        preferencesObservation = model.$preferences.removeDuplicates().sink { [weak self] preferences in
            guard let self, self.started else { return }
            self.controller.updater.automaticallyChecksForUpdates = preferences.automaticallyCheckUpdates
        }
        sessionObservation = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.resumeIfReady() }
        }
    }
    /// Sparkle's windows open at the normal level, which hides them behind Dice when it stays on top.
    private func raiseUpdaterWindows() {
        windowObservation = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, let self else { return }
            let owner = window.windowController.map { String(describing: type(of: $0)) } ?? ""
            guard owner.contains("SU") || String(describing: type(of: window)).hasPrefix("SU") else { return }
            MainActor.assumeIsolated {
                if self.model.preferences.stayOnTop { window.level = .modalPanel; window.orderFrontRegardless() }
            }
        }
    }
    func start() {
        raiseUpdaterWindows()
        guard Bundle.main.object(forInfoDictionaryKey: "DiceDevelopmentBuild") as? Bool != true else { return }
        controller.startUpdater(); started = true
        controller.updater.automaticallyChecksForUpdates = model.preferences.automaticallyCheckUpdates
    }
    func check(_ sender: Any?) {
        guard Bundle.main.object(forInfoDictionaryKey: "DiceDevelopmentBuild") as? Bool != true else {
            model.alert = "This is a development copy. Open Dice in Applications to check for release updates."
            return
        }
        guard !model.busy && !model.importing else {
            model.alert = "Finish the current images before checking for updates."
            return
        }
        controller.checkForUpdates(sender)
    }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { includePreviews ? ["preview"] : [] }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard model.busy || model.importing || !model.unsavedResults.isEmpty else { return false }
        pendingInstall = installHandler
        model.alert = "Your update is ready. Save your processed copies, then close the Dice window to finish installing it."
        return true
    }
    private func resumeIfReady() {
        guard !model.busy && !model.importing && model.items.isEmpty, let install = pendingInstall else { return }
        pendingInstall = nil
        install()
    }
}
