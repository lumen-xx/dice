import Foundation
import DiceCore

enum ExportMode: String, Codable, CaseIterable, Identifiable {
    case save = "Save copies", clipboard = "Copy to clipboard"
    var id: String { rawValue }
}
struct AppPreferences: Codable, Equatable {
    var useExportFolder = false
    var exportFolder = ""
    var useExportFormat = false
    var exportFormat: OutputFormat = .png
    var automaticallyCheckUpdates = false
    var defaultQuality = 0.82
    var defaultResize: ResizeMode = .original
    var defaultEdge = 1920
    var defaultPercent = 50
    var startAtLogin = false
    var showInMenuBar = false
    var stayOnTop = false
    var defaultReplaceOriginals = false
    var defaultStripMetadata = true
    var alwaysStripMetadata = false
    var flattenColor: [Double] = [1, 1, 1]
    var keepAnimation = true
    var framesAsFolder = true
    var fileSuffix = "-dice"
    var closeWhenDone = true
    var exportMode: ExportMode = .save
    var menuBarDrop = true
    var dropStartsImmediately = false
    var dragTarget: DragTarget = .off
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppPreferences()
        useExportFolder = try c.decodeIfPresent(Bool.self, forKey: .useExportFolder) ?? d.useExportFolder
        exportFolder = try c.decodeIfPresent(String.self, forKey: .exportFolder) ?? d.exportFolder
        useExportFormat = try c.decodeIfPresent(Bool.self, forKey: .useExportFormat) ?? d.useExportFormat
        exportFormat = try c.decodeIfPresent(OutputFormat.self, forKey: .exportFormat) ?? d.exportFormat
        automaticallyCheckUpdates = try c.decodeIfPresent(Bool.self, forKey: .automaticallyCheckUpdates) ?? d.automaticallyCheckUpdates
        defaultQuality = try c.decodeIfPresent(Double.self, forKey: .defaultQuality) ?? d.defaultQuality
        defaultResize = try c.decodeIfPresent(ResizeMode.self, forKey: .defaultResize) ?? d.defaultResize
        defaultEdge = try c.decodeIfPresent(Int.self, forKey: .defaultEdge) ?? d.defaultEdge
        defaultPercent = try c.decodeIfPresent(Int.self, forKey: .defaultPercent) ?? d.defaultPercent
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? d.startAtLogin
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? d.showInMenuBar
        stayOnTop = try c.decodeIfPresent(Bool.self, forKey: .stayOnTop) ?? d.stayOnTop
        defaultReplaceOriginals = try c.decodeIfPresent(Bool.self, forKey: .defaultReplaceOriginals) ?? d.defaultReplaceOriginals
        defaultStripMetadata = try c.decodeIfPresent(Bool.self, forKey: .defaultStripMetadata) ?? d.defaultStripMetadata
        alwaysStripMetadata = try c.decodeIfPresent(Bool.self, forKey: .alwaysStripMetadata) ?? d.alwaysStripMetadata
        flattenColor = try c.decodeIfPresent([Double].self, forKey: .flattenColor) ?? d.flattenColor
        keepAnimation = try c.decodeIfPresent(Bool.self, forKey: .keepAnimation) ?? d.keepAnimation
        framesAsFolder = try c.decodeIfPresent(Bool.self, forKey: .framesAsFolder) ?? d.framesAsFolder
        fileSuffix = try c.decodeIfPresent(String.self, forKey: .fileSuffix) ?? d.fileSuffix
        closeWhenDone = try c.decodeIfPresent(Bool.self, forKey: .closeWhenDone) ?? d.closeWhenDone
        exportMode = try c.decodeIfPresent(ExportMode.self, forKey: .exportMode) ?? d.exportMode
        menuBarDrop = try c.decodeIfPresent(Bool.self, forKey: .menuBarDrop) ?? d.menuBarDrop
        dropStartsImmediately = try c.decodeIfPresent(Bool.self, forKey: .dropStartsImmediately) ?? d.dropStartsImmediately
        dragTarget = (try? c.decodeIfPresent(DragTarget.self, forKey: .dragTarget)) ?? d.dragTarget
    }
}

/// One-off destinations offered by the popover on the start button.
enum ExportAction: String, CaseIterable, Identifiable {
    case beside, folder, replace, clipboard, edit
    var id: String { rawValue }
}
