import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home    = "Home"
        case apps    = "Apps"
        case device  = "Device"
        case log     = "Log"
        case diag    = "Diag"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("iOS Notify")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text(selectedTab.rawValue.uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Theme.surface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)

            // Content
            ZStack {
                switch selectedTab {
                case .home:   HomeView()
                case .apps:   AppSelectionView()
                case .device: DeviceView()
                case .log:    NotificationLogView()
                case .diag:   DiagView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tab bar
            Divider().background(Theme.border)
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button(tab.rawValue) { selectedTab = tab }
                        .font(.system(size: 12,
                                      weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? Theme.accent : Theme.dimText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(Theme.surface)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
