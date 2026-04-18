import Foundation

@MainActor
class ShortcutsTriggerManager: ObservableObject {
    static let shared = ShortcutsTriggerManager()

    @Published var shortcutName: String = "iOS Notify Received"

    private let nameKey = "stm_scname_v1"

    init() {
        shortcutName = UserDefaults.standard.string(forKey: nameKey) ?? "iOS Notify Received"
    }

    func saveSettings() {
        UserDefaults.standard.set(shortcutName, forKey: nameKey)
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
}
