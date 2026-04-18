import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // NotificationManager.init() already sets the delegate; this ensures it's set
        // early even before ContentView initialises the singleton via @ObservedObject.
        _ = NotificationManager.shared
        let bg = launchOptions?[.sourceApplication] != nil || application.applicationState == .background
        Task { @MainActor in
            DiagnosticLog.shared.log("App launched — background=\(bg) state=\(application.applicationState.rawValue)", tag: "LIFECYCLE")
            let apps = AppListManager.shared.monitoredApps
            if apps.isEmpty {
                DiagnosticLog.shared.log("No apps in monitored list — add apps in the Apps tab", tag: "LIFECYCLE")
            } else {
                for app in apps {
                    DiagnosticLog.shared.log(
                        "Monitored: \(app.displayName) [\(app.bundleIdentifier)] band=\(app.forwardToBand) shortcut=\(app.useAsShortcutTrigger)",
                        tag: "LIFECYCLE"
                    )
                }
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}
