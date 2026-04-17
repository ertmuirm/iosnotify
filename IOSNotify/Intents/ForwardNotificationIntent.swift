import AppIntents

// iOS 17+ AutomationTrigger — appears under IOSNotify in Shortcuts > New Automation.
// When IOSNotify detects a notification from a configured app it posts this trigger,
// causing any Shortcuts automation that uses it to fire.
@available(iOS 17.0, *)
struct NotificationReceivedTrigger: AutomationTrigger {
    static let title: LocalizedStringResource = "Notification Received"
    static let description = IntentDescription(
        "Triggers when a notification arrives from one of your monitored apps."
    )

    @Parameter(title: "From App", description: "The app whose notifications activate this automation.")
    var app: MonitoredAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("When a notification arrives from \(\.$app)")
    }
}

// Provides the trigger in the Shortcuts app gallery.
@available(iOS 17.0, *)
struct IOSNotifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] { [] }
    static var automationTriggers: [AutomationTriggerAppShortcut] {
        [AutomationTriggerAppShortcut(trigger: NotificationReceivedTrigger.self)]
    }
}
