import AppIntents

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
    // Called by Shortcuts at automation run-time to resolve saved entity identifiers.
    // Must never return an empty array for a requested identifier — if the app list
    // isn't loaded (e.g. background launch), fall back to a stub so perform() still runs.
    func entities(for identifiers: [String]) async throws -> [MonitoredAppEntity] {
        await MainActor.run {
            let saved = AppListManager.shared.monitoredApps
            return identifiers.map { id in
                saved.first(where: { $0.bundleIdentifier == id })
                    .map { MonitoredAppEntity(app: $0) }
                    ?? MonitoredAppEntity(bundleId: id, displayName: id)
            }
        }
    }

    func suggestedEntities() async throws -> [MonitoredAppEntity] {
        await MainActor.run {
            AppListManager.shared.monitoredApps.map { MonitoredAppEntity(app: $0) }
        }
    }
}
