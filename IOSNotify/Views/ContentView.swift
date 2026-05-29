import SwiftUI

struct ContentView: View {
    @State private var showAutomation = false
    @ObservedObject private var automation = AutomationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notify")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                automationBadge
                bluetoothStatusBadge
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Theme.surface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)

            DeviceListView()
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAutomation) {
            AutomationSettingsView()
        }
    }

    private var automationBadge: some View {
        Button {
            showAutomation = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: automation.isPlayerRunning ? "bolt.fill" : "bolt")
                    .font(.system(size: 10, weight: .bold))
                Text(automation.isPlayerRunning ? "AUTO ON" : "AUTO")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(automation.isPlayerRunning ? Theme.accent : Theme.dimText)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .stroke(automation.isPlayerRunning ? Theme.accent : Theme.dimText,
                        lineWidth: 1))
        }
        .padding(.trailing, 8)
    }

    private var btBadgeInfo: (label: String, color: Color) {
        switch BluetoothManager.shared.bluetoothState {
        case .poweredOn:  return ("BT ON",  Theme.accent)
        case .poweredOff: return ("BT OFF", Theme.dimText)
        default:          return ("BT …",   Theme.dimText)
        }
    }

    private var bluetoothStatusBadge: some View {
        let info = btBadgeInfo
        return Text(info.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(info.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(info.color, lineWidth: 1))
    }
}
