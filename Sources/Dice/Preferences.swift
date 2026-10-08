import Foundation
import DiceCore

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
    }
}
