import Foundation
import Combine

class AppListManager: ObservableObject {
    static let shared = AppListManager()

    @Published var monitoredApps: [MonitoredApp] = []

    private let storageKey = "monitoredApps_v1"

    init() {
        load()
    }

    func add(bundleId: String, displayName: String) {
        guard !monitoredApps.contains(where: { $0.bundleIdentifier == bundleId }) else { return }
        monitoredApps.append(MonitoredApp(bundleIdentifier: bundleId, displayName: displayName))
        save()
    }

    func remove(id: UUID) {
        monitoredApps.removeAll { $0.id == id }
        save()
    }

    func update(_ app: MonitoredApp) {
        guard let index = monitoredApps.firstIndex(where: { $0.id == app.id }) else { return }
        monitoredApps[index] = app
        save()
    }

    func app(for bundleId: String) -> MonitoredApp? {
        monitoredApps.first { $0.bundleIdentifier == bundleId }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(monitoredApps) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let apps = try? JSONDecoder().decode([MonitoredApp].self, from: data) else { return }
        monitoredApps = apps
    }
}
