import SwiftUI

enum Theme {
    static let background = Color(hex: "000000")
    static let text = Color(hex: "FFFFFF")
    static let accent = Color(hex: "E0E0E0")
    static let surface = Color(hex: "0D0D0D")
    static let border = Color(hex: "2A2A2A")
    static let dimText = Color(hex: "666666")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct ThemedButtonStyle: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(filled ? Theme.background : Theme.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(filled ? Theme.accent : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// Used by both DeviceListView and AutomationSettingsView for per-row settings panels.
extension View {
    func settingsRow() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.surface.opacity(0.6))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }
}

struct RowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }
}
