import AppIntents
import UIKit

struct NotificationReceivedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Notification"
    static var description = IntentDescription(
        "Logs a notification in iOS Notify, forwards it to your band, and triggers your Shortcuts automation."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "From App")
    var app: MonitoredAppEntity

    @Parameter(title: "Notification Title", default: "")
    var notifTitle: String

    @Parameter(title: "Notification Body", default: "")
    var notifBody: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log notification from \(\.$app): \(\.$notifTitle)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await MainActor.run {
            DiagnosticLog.shared.log(
                "AppIntent.perform: app=\(app.displayName) id=\(app.id) title=\(notifTitle.prefix(60))",
                tag: "INTENT"
            )
            NotificationManager.shared.ingest(
                bundleId: app.id,
                appName: app.displayName,
                title: notifTitle,
                body: notifBody
            )

            // If this app has "Shortcut trigger" enabled, open the named Shortcut directly.
            // Fires immediately, no user interaction needed.
            let appList = AppListManager.shared
            if let monitored = appList.app(for: app.id), monitored.useAsShortcutTrigger {
                let triggerMgr = ShortcutsTriggerManager.shared
                if let url = triggerMgr.shortcutsURL(
                    appName: app.displayName,
                    bundleId: app.id,
                    title: notifTitle,
                    body: notifBody
                ) {
                    DiagnosticLog.shared.log("Opening: \(url.absoluteString.prefix(100))", tag: "TRIGGER")
                    UIApplication.shared.open(url, options: [:]) { success in
                        Task { @MainActor in
                            DiagnosticLog.shared.log("shortcuts:// open result=\(success)", tag: "TRIGGER")
                        }
                    }
                } else {
                    DiagnosticLog.shared.log("shortcutsURL: no shortcut name configured", tag: "TRIGGER")
                }
            }
        }

        return .result(value: "[\(app.displayName)] \(notifTitle)")
    }
}

struct IOSNotifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NotificationReceivedIntent(),
            phrases: ["Log notification via \(.applicationName)"],
            shortTitle: "Log Notification",
            systemImageName: "bell.badge"
        )
    }
}
