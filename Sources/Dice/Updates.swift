import AppKit
import Sparkle
import Combine

@MainActor final class DiceUpdates: NSObject, SPUUpdaterDelegate {
    private let model: DiceModel
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var pendingInstall: (() -> Void)?
    private var sessionObservation: AnyCancellable?
    var includePreviews: Bool {
        get { UserDefaults.standard.object(forKey: "dice.previewUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dice.previewUpdates") }
    }

    init(model: DiceModel) {
        self.model = model
        super.init()
        sessionObservation = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.resumeIfReady() }
        }
    }
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "DiceDevelopmentBuild") as? Bool != true else { return }
        controller.startUpdater()
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
        guard model.busy || model.importing || !model.results.isEmpty else { return false }
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
