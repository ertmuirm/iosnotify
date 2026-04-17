import AppIntents

// Shortcuts action exposed by IOSNotify.
// IOSNotify also posts a passive local notification for each forwarded event so that
// Shortcuts "Notification Received from IOSNotify" can be used as an automation trigger.
// Format: "[AppName] title" — users can filter by app name using Shortcuts text matching.
struct NotificationReceivedIntent: AppIntent {
    static var title: LocalizedStringResource = "Notification Received"
    static var description = IntentDescription(
        "Runs when IOSNotify detects a notification from a monitored app."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "From App")
    var app: MonitoredAppEntity

    @Parameter(title: "Title", default: "")
    var notificationTitle: String

    @Parameter(title: "Body", default: "")
    var notificationBody: String

    static var parameterSummary: some ParameterSummary {
        Summary("Notification from \(\.$app): \(\.$notificationTitle)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: "[\(app.displayName)] \(notificationTitle)")
    }
}

struct IOSNotifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NotificationReceivedIntent(),
            phrases: ["Notification via IOSNotify"],
            shortTitle: "Notification Received",
            systemImageName: "bell.badge"
        )
    }
}
