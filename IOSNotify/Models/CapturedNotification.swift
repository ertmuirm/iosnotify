import Foundation

struct CapturedNotification: Identifiable, Codable {
    var id: UUID
    var appBundleId: String
    var appName: String
    var title: String
    var body: String
    var timestamp: Date
    var forwardedToBand: Bool
    var usedAsShortcutTrigger: Bool

    init(appBundleId: String, appName: String, title: String, body: String) {
        self.id = UUID()
        self.appBundleId = appBundleId
        self.appName = appName
        self.title = title
        self.body = body
        self.timestamp = Date()
        self.forwardedToBand = false
        self.usedAsShortcutTrigger = false
    }
}
