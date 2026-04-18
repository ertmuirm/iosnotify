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

    // Posts a visible local notification from IOSNotify so Shortcuts
    // "Notification Received → IOSNotify" automations fire.
    // Title format "[AppName] title" lets users filter by app name via text matching.
    // Must be visible (not passive) for Shortcuts to recognise it as a trigger source.
    private func postShortcutTrigger(displayName: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "[\(displayName)] \(title)"
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // Sends one visible notification immediately so IOSNotify appears in the
    // Shortcuts "Notification Received" trigger source list straight away.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "IOSNotify is active"
        content.body = "Go to Shortcuts → Automation → + → Notification Received → IOSNotify."
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
