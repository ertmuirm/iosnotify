import Foundation
import UserNotifications
import Combine

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var recentNotifications: [CapturedNotification] = []

    private let storageKey = "recentNotifications_v1"
    private let maxStored = 200

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        loadHistory()
        refreshStatus()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .provisional]) { _, _ in
            self.refreshStatus()
        }
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.authorizationStatus = settings.authorizationStatus }
        }
    }

    // Called when app is in foreground and a notification arrives for this app
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        process(notification.request.content)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        process(response.notification.request.content)
        completionHandler()
    }

    private func process(_ content: UNNotificationContent) {
        let bundleId = content.userInfo["sourceBundle"] as? String ?? ""
        let appName = content.userInfo["sourceName"] as? String ?? "IOSNotify"
        ingest(bundleId: bundleId, appName: appName, title: content.title, body: content.body)
    }

    // Entry point for all detected notifications — forwards to BLE band, fires Shortcuts
    // passive notification trigger, and logs the event.
    func ingest(bundleId: String, appName: String, title: String, body: String) {
        var captured = CapturedNotification(appBundleId: bundleId, appName: appName, title: title, body: body)

        let appList = AppListManager.shared
        if let monitored = appList.app(for: bundleId) {
            if monitored.forwardToBand {
                BluetoothManager.shared.sendNotification(appName: appName, title: title, body: body)
                captured.forwardedToBand = true
            }
            if monitored.useAsShortcutTrigger {
                captured.usedAsShortcutTrigger = true
                postShortcutTrigger(displayName: monitored.displayName, title: title, body: body)
            }
        }

        DispatchQueue.main.async {
            self.recentNotifications.insert(captured, at: 0)
            if self.recentNotifications.count > self.maxStored {
                self.recentNotifications = Array(self.recentNotifications.prefix(self.maxStored))
            }
            self.persistHistory()
        }
    }

    // Delivers a silent local notification from IOSNotify so the Shortcuts
    // "Notification Received → IOSNotify" automation trigger fires.
    // No sound is set — the user should also disable banners for IOSNotify in
    // iOS Settings so these never surface visually.
    // Title format "[AppName] title" allows per-app filtering in Shortcuts.
    private func postShortcutTrigger(displayName: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "[\(displayName)] \(title)"
        content.body = body
        // No sound — delivery is enough to fire the Shortcuts trigger
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // Sends one notification so IOSNotify immediately appears in the Shortcuts
    // "Notification Received" trigger source list. After tapping this, the user
    // should go to iOS Settings → IOSNotify → Notifications → disable Banners
    // and Sound so future relay notifications never show on screen.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "IOSNotify registered"
        content.body = "Now go to iOS Settings → IOSNotify → Notifications → disable Banners & Sound. Then set up your Shortcuts automation."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "iosnotify.test", content: content, trigger: nil)
        )
    }

    private func persistHistory() {
        let slice = Array(recentNotifications.prefix(50))
        if let data = try? JSONEncoder().encode(slice) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([CapturedNotification].self, from: data) else { return }
        recentNotifications = items
    }
}
