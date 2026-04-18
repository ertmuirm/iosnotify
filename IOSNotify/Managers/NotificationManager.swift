import Foundation
import UserNotifications
import Combine

@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var recentNotifications: [CapturedNotification] = []
    @Published var isRecording: Bool = true

    private let storageKey  = "recentNotifications_v1"
    private let recordingKey = "isRecording_v1"
    private let maxStored   = 200

    // Prefix used in relay notification identifiers so willPresent can skip them.
    static let relayPrefix = "__iosnotify_relay__"

    override init() {
        super.init()
        isRecording = UserDefaults.standard.object(forKey: recordingKey) as? Bool ?? true
        UNUserNotificationCenter.current().delegate = self
        loadHistory()
        refreshStatus()
        DiagnosticLog.shared.log("NotificationManager init — isRecording=\(isRecording)", tag: "LIFECYCLE")
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in self.refreshStatus() }
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.authorizationStatus = settings.authorizationStatus }
        }
    }

    func setRecording(_ on: Bool) {
        isRecording = on
        UserDefaults.standard.set(on, forKey: recordingKey)
        DiagnosticLog.shared.log("Recording set to \(on)", tag: "APP")
    }

    func clearHistory() {
        recentNotifications = []
        UserDefaults.standard.removeObject(forKey: storageKey)
        DiagnosticLog.shared.log("History cleared", tag: "APP")
    }

    // Called when app is in foreground and a notification for this app arrives.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        DiagnosticLog.shared.log("willPresent: id=\(notification.request.identifier) title=\(content.title.prefix(60))", tag: "NOTIF")

        // Skip relay notifications to avoid double-logging them as "iOS Notify" entries.
        if notification.request.identifier.hasPrefix(Self.relayPrefix) {
            completionHandler([])
            return
        }

        process(content)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        DiagnosticLog.shared.log("didReceive: id=\(response.notification.request.identifier) title=\(content.title.prefix(60))", tag: "NOTIF")
        if !response.notification.request.identifier.hasPrefix(Self.relayPrefix) {
            process(content)
        }
        completionHandler()
    }

    private func process(_ content: UNNotificationContent) {
        let bundleId = content.userInfo["sourceBundle"] as? String ?? ""
        let appName  = content.userInfo["sourceName"]  as? String ?? "iOS Notify"
        DiagnosticLog.shared.log("process: bundle=\(bundleId) app=\(appName)", tag: "NOTIF")
        ingest(bundleId: bundleId, appName: appName, title: content.title, body: content.body)
    }

    // Entry point for all detected notifications.
    // Called from the Shortcuts AppIntent (ForwardNotificationIntent) for third-party
    // notifications the user routes via a Shortcuts automation.
    func ingest(bundleId: String, appName: String, title: String, body: String) {
        DiagnosticLog.shared.log("ingest: bundle=\(bundleId) app=\(appName) title=\(title.prefix(60)) recording=\(isRecording)", tag: "INGEST")

        var captured = CapturedNotification(appBundleId: bundleId, appName: appName,
                                            title: title, body: body)
        let appList = AppListManager.shared
        DiagnosticLog.shared.log("ingest: monitoredApps count=\(appList.monitoredApps.count)", tag: "INGEST")

        if let monitored = appList.app(for: bundleId) {
            if monitored.forwardToBand {
                BluetoothManager.shared.sendNotification(appName: appName, title: title, body: body)
                captured.forwardedToBand = true
                DiagnosticLog.shared.log("ingest: forwarded to band", tag: "INGEST")
            }
            if monitored.useAsShortcutTrigger {
                captured.usedAsShortcutTrigger = true
                let triggerMgr = ShortcutsTriggerManager.shared
                switch triggerMgr.triggerMode {
                case .message:
                    if !triggerMgr.phoneNumber.isEmpty {
                        triggerMgr.enqueue(appName: appName, title: title, body: body)
                    } else {
                        DiagnosticLog.shared.log("ingest: message trigger — no phone number set", tag: "INGEST")
                    }
                case .shortcutsURL:
                    // The URL is opened from ForwardNotificationIntent.perform() because
                    // UIApplication.open() must be called from the active app process, not here.
                    DiagnosticLog.shared.log("ingest: shortcutsURL mode — will be fired by AppIntent", tag: "INGEST")
                }
            }
        } else {
            DiagnosticLog.shared.log("ingest: bundle not in monitored list — still logging", tag: "INGEST")
        }

        guard isRecording else {
            DiagnosticLog.shared.log("ingest: skipped — recording is off", tag: "INGEST")
            return
        }
        recentNotifications.insert(captured, at: 0)
        if recentNotifications.count > maxStored {
            recentNotifications = Array(recentNotifications.prefix(maxStored))
        }
        persistHistory()
        DiagnosticLog.shared.log("ingest: saved — total=\(recentNotifications.count)", tag: "INGEST")
    }

    // Sends a notification after a 5-second delay so the user has time to background the
    // app. The notification must arrive while backgrounded for iOS to register iOS Notify
    // in the Shortcuts "Notification Received" trigger list.
    func sendRegistrationNotification() {
        let content = UNMutableNotificationContent()
        content.title = "iOS Notify registered"
        content.body = "iOS Notify will now appear in Shortcuts → Automation → Notification Received."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "iosnotify.register", content: content, trigger: trigger)
        )
        DiagnosticLog.shared.log("Registration notification scheduled (5s delay)", tag: "APP")
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
        DiagnosticLog.shared.log("loadHistory: loaded \(items.count) items", tag: "LIFECYCLE")
    }
}
