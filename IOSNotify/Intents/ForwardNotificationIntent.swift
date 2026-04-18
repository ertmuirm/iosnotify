import AppIntents

// Shortcuts action: call this from a Shortcuts automation whose trigger is
// "Notification Received from [any third-party app]". The intent logs the
// notification to iOS Notify's Recent Activity, forwards it to the BLE band
// (if enabled for that app), and posts a relay notification so the
// "Notification Received from iOS Notify" Shortcuts trigger fires.
struct NotificationReceivedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Notification"
    static var description = IntentDescription(
        "Logs a notification in iOS Notify, forwards it to your band, and fires the iOS Notify Shortcuts trigger."
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
