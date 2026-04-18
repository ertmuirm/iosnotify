import Foundation

@MainActor
class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    struct Entry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let tag: String
        let message: String

        init(tag: String, message: String) {
            self.id = UUID()
            self.timestamp = Date()
            self.tag = tag
            self.message = message
        }
    }

    @Published var entries: [Entry] = []
    private let maxEntries = 300
    private let storageKey = "diagLog_v1"

    init() { load() }

    func log(_ message: String, tag: String = "APP") {
        let e = Entry(tag: tag, message: message)
        entries.insert(e, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        persist()
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(entries.prefix(200))) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = items
    }
}
