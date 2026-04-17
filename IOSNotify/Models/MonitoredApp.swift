import Foundation

struct MonitoredApp: Identifiable, Codable, Hashable {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String
    var forwardToBand: Bool
    var useAsShortcutTrigger: Bool

    init(bundleIdentifier: String, displayName: String) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.forwardToBand = true
        self.useAsShortcutTrigger = false
    }
}
