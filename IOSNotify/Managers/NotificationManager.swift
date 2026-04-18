import Foundation
import UserNotifications
import Combine

@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var recentNotifications: [CapturedNotification] = []
    @Published var isRecording: Bool = true

    private let storageKey = "recentNotifications_v1"
    private let recordingKey = "isRecording_v1"
    private let maxStored = 200

    override init() {
        super.init()
        isRecording = UserDefaults.standard.object(forKey: recordingKey) as? Bool ?? true
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

    func setRecording(_ on: Bool) {
        isRecording = on
        UserDefaults.standard.set(on, forKey: recordingKey)
    }

    func clearHistory() {
        recentNotifications = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // Called when app is in foreground and a notification for this app arrives.
    // Third-party app notifications arrive here only when routed via a Shortcuts
    // automation that calls the "Log Notification" AppIntent action.
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
        let appName = content.userInfo["sourceName"] as? String ?? "iOS Notify"
        ingest(bundleId: bundleId, appName: appName, title: content.title, body: content.body)
    }

    // Entry point for all detected notifications.
    // Called either from the UNUserNotificationCenterDelegate (for self-notifications)
    // or from the Shortcuts AppIntent (for third-party app notifications routed via Shortcuts).
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

        guard isRecording else { return }
        recentNotifications.insert(captured, at: 0)
        if recentNotifications.count > maxStored {
            recentNotifications = Array(recentNotifications.prefix(maxStored))
        }
        persistHistory()
    }

    // Delivers a local notification from iOS Notify so the Shortcuts
    // "Notification Received → iOS Notify" automation trigger fires.
    // Title "[AppName] title" lets users filter by app name in Shortcuts.
    // Tip: disable banners for iOS Notify in iOS Settings to hide these.
    private func postShortcutTrigger(displayName: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "[\(displayName)] \(title)"
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // Call once to make iOS Notify appear in Shortcuts "Notification Received" list.
    // After tapping this, go to iOS Settings → iOS Notify → Notifications →
    // set Alert Style to None so future relay notifications are invisible.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "iOS Notify registered"
        content.body = "Next: iOS Settings → iOS Notify → Notifications → Alert Style: None. Then create your Shortcuts automation."
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
