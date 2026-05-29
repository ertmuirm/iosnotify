import Foundation

enum MatchStrategy: String, Codable, CaseIterable {
    case all = "All Conditions (AND)"
    case any = "Any Condition (OR)"
}

enum TargetOrientation: String, Codable, CaseIterable, Identifiable {
    case portrait       = "Portrait"
    case landscapeLeft  = "Landscape Left"
    case landscapeRight = "Landscape Right"
    case faceUp         = "Face Up"
    case faceDown       = "Face Down"
    var id: String { rawValue }
}

struct AutomationConfig: Codable {
    var isEnabled: Bool             = false
    var shortcutName: String        = "Display On"
    var matchStrategy: MatchStrategy = .all

    // Condition 1 – Focus / DND
    var focusEnabled: Bool          = false

    // Condition 2 – Wi-Fi SSID
    var wifiEnabled: Bool           = false
    var wifiSSID: String            = ""

    // Condition 3 – Charging state
    var chargingEnabled: Bool       = false

    // Condition 4 – Time range
    var timeRangeEnabled: Bool      = false
    var timeRangeStart: Date        = {
        Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    }()
    var timeRangeEnd: Date          = {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }()

    // Condition 5 – Device orientation
    var orientationEnabled: Bool    = false
    var targetOrientation: TargetOrientation = .faceUp

    // MARK: - Persistence

    static let defaultsKey = "automationConfig_v1"

    static func load() -> AutomationConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let cfg  = try? JSONDecoder().decode(AutomationConfig.self, from: data)
        else { return AutomationConfig() }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AutomationConfig.defaultsKey)
        }
    }
}
