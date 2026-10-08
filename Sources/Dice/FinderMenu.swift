import AppKit

/// Shows or hides Dice's "Edit with Dice" item in Finder's right-click menu by editing the system Services
/// status (the same list as System Settings → Keyboard → Keyboard Shortcuts → Services).
enum FinderMenu {
    static let statusKey = "com.opyuii.dice - Edit with Dice - editWithDice"
    private static let domain = "pbs" as CFString

    static var isAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "NSServices") != nil }

    static var isEnabled: Bool {
        let all = CFPreferencesCopyAppValue("NSServicesStatus" as CFString, domain) as? [String: Any]
        let entry = all?[statusKey] as? [String: Any]
        return (entry?["enabled_context_menu"] as? Bool) ?? ((entry?["enabled_context_menu"] as? NSNumber)?.boolValue ?? true)
    }

    static func setEnabled(_ enabled: Bool) {
        var all = (CFPreferencesCopyAppValue("NSServicesStatus" as CFString, domain) as? [String: Any]) ?? [:]
        var entry = (all[statusKey] as? [String: Any]) ?? [:]
        entry["enabled_context_menu"] = enabled
        if entry["enabled_services_menu"] == nil { entry["enabled_services_menu"] = true }
        all[statusKey] = entry
        CFPreferencesSetAppValue("NSServicesStatus" as CFString, all as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        NSUpdateDynamicServices()
    }
}
