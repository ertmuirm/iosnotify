import AppIntents

// Entity representing one of the user's configured monitored apps.
// Appears in the Shortcuts trigger parameter picker.
struct MonitoredAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static var defaultQuery = MonitoredAppQuery()

    var id: String          // bundle identifier
    var displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    init(bundleId: String, displayName: String) {
        self.id = bundleId
        self.displayName = displayName
    }

    init(app: MonitoredApp) {
        self.id = app.bundleIdentifier
        self.displayName = app.displayName
    }
}

struct MonitoredAppQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MonitoredAppEntity] {
        await MainActor.run {
            AppListManager.shared.monitoredApps
                .filter { identifiers.contains($0.bundleIdentifier) }
                .map { MonitoredAppEntity(app: $0) }
        }
    }

    func suggestedEntities() async throws -> [MonitoredAppEntity] {
        await MainActor.run {
            AppListManager.shared.monitoredApps.map { MonitoredAppEntity(app: $0) }
        }
    }
}
