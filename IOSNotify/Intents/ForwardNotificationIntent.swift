import AppIntents

// Shortcuts action: "Forward Notification to Band / Shortcut Trigger"
// Users create Shortcuts automations triggered by notifications from specific apps,
// then call this intent to route them to the band or log them as trigger events.
struct ForwardNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Forward Notification"
    static var description = IntentDescription(
        "Forwards a notification from any app to your connected smart band, " +
        "and logs it as a Shortcut trigger event in IOSNotify."
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Forward notification from \(\.$appName): \(\.$title)")
    }

    @Parameter(title: "App Name")
    var appName: String

    @Parameter(title: "Bundle ID", default: "")
    var bundleId: String

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Body", default: "")
    var body: String

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        await MainActor.run {
            NotificationManager.shared.ingest(
                bundleId: bundleId,
                appName: appName,
                title: title,
                body: body
            )
        }
        return .result(value: true)
    }
}

struct IOSNotifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ForwardNotificationIntent(),
            phrases: ["Forward notification via IOSNotify"],
            shortTitle: "Forward Notification",
            systemImageName: "bell.badge"
        )
    }
}
