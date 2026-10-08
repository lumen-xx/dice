import Foundation
import DiceCore

struct AppPreferences: Codable, Equatable {
    var useExportFolder = false
    var exportFolder = ""
    var useExportFormat = false
    var exportFormat: OutputFormat = .png
    var automaticallyCheckUpdates = false
}
