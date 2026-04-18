import Foundation

enum TriggerMode: String, CaseIterable, Codable, Identifiable {
    case shortcutsURL = "Run Shortcut (URL)"
    case message      = "iMessage to Self"

    var id: String { rawValue }
}

@MainActor
class ShortcutsTriggerManager: ObservableObject {
    static let shared = ShortcutsTriggerManager()

    struct PendingMessage: Identifiable, Codable {
        let id: UUID
        let appName: String
        let title: String
        let body: String
        let timestamp: Date
    }

    @Published var triggerMode: TriggerMode = .shortcutsURL
    @Published var shortcutName: String = "iOS Notify Received"
    @Published var phoneNumber: String = ""
    @Published var pendingMessages: [PendingMessage] = []

    private let modeKey    = "stm_mode_v1"
    private let nameKey    = "stm_scname_v1"
    private let phoneKey   = "stm_phone_v1"
    private let queueKey   = "stm_queue_v1"

    init() { loadAll() }

    // Called from NotificationManager.ingest() when the app has useAsShortcutTrigger=true
    // and the user is in message mode.
    func enqueue(appName: String, title: String, body: String) {
        pendingMessages.append(PendingMessage(id: UUID(), appName: appName, title: title,
                                              body: body, timestamp: Date()))
        saveQueue()
        DiagnosticLog.shared.log("Queued: \(appName) — \(title.prefix(50))", tag: "TRIGGER")
    }

    // Returns all queued messages as a single string for the compose view, then empties queue.
    func drainAsText() -> String? {
        guard !pendingMessages.isEmpty else { return nil }
        let text = pendingMessages.map { msg -> String in
            var line = "🔔 [\(msg.appName)] \(msg.title)"
            if !msg.body.isEmpty { line += "\n\(msg.body)" }
            return line
        }.joined(separator: "\n\n")
        pendingMessages.removeAll()
        saveQueue()
        return text
    }

    func clearQueue() {
        pendingMessages.removeAll()
        saveQueue()
    }

    // Builds the shortcuts:// URL to call a named Shortcut with notification JSON as input.
    func shortcutsURL(appName: String, bundleId: String, title: String, body: String) -> URL? {
        guard !shortcutName.isEmpty else { return nil }
        let input: [String: String] = [
            "app": appName, "bundle": bundleId, "title": title, "body": body
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              let jsonString = String(data: json, encoding: .utf8),
              let encodedJSON = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedName = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "shortcuts://run-shortcut?name=\(encodedName)&input=\(encodedJSON)")
    }

    func saveSettings() {
        UserDefaults.standard.set(triggerMode.rawValue, forKey: modeKey)
        UserDefaults.standard.set(shortcutName, forKey: nameKey)
        UserDefaults.standard.set(phoneNumber, forKey: phoneKey)
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(pendingMessages) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    private func loadAll() {
        if let raw = UserDefaults.standard.string(forKey: modeKey),
           let mode = TriggerMode(rawValue: raw) { triggerMode = mode }
        shortcutName = UserDefaults.standard.string(forKey: nameKey) ?? "iOS Notify Received"
        phoneNumber  = UserDefaults.standard.string(forKey: phoneKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let msgs = try? JSONDecoder().decode([PendingMessage].self, from: data) {
            pendingMessages = msgs
        }
    }
}
