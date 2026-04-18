import SwiftUI
import CoreBluetooth

struct DeviceListView: View {
    @ObservedObject private var bt = BluetoothManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                sectionHeader("BONDED DEVICES")

                if bt.bondedDevices.isEmpty {
                    Text("No devices bonded yet. Scan and tap Bond to pair a device.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dimText)
                        .padding(16)
                } else {
                    ForEach(bt.bondedDevices) { device in
                        bondedRow(device)
                    }
                }

                sectionHeader("SCAN")

                Button(bt.isScanning ? "Stop Scanning" : "Scan for Devices") {
                    bt.isScanning ? bt.stopScan() : bt.startScan()
                }
                .buttonStyle(ThemedButtonStyle())
                .padding(16)

                if bt.isScanning {
                    Text("Scanning for nearby BLE devices… (15 s)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.dimText)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if !bt.discoveredDevices.isEmpty {
                    sectionHeader("DISCOVERED")
                    ForEach(bt.discoveredDevices, id: \.identifier) { peripheral in
                        discoveredRow(peripheral)
                    }
                }

                sectionHeader("NOTIFICATION CATEGORIES")

                ForEach(NotifCategory.allCases) { category in
                    categoryRow(category)
                }

                sectionHeader("SETTINGS")

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Auto-reconnect")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                        Text("Reconnect in the background if a bonded device drops")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.dimText)
                    }
                    Spacer()
                    Toggle("", isOn: $bt.autoReconnect)
                        .labelsHidden()
                        .tint(Theme.accent)
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)

                sectionHeader("HOW IT WORKS")

                infoRow("The app connects using the FitPro Nordic UART protocol and")
                infoRow("sends a CMD_NOTIFICATIONS_ENABLE command to the band after")
                infoRow("each connection. The category toggles above control which")
                infoRow("of the 11 payload bytes are set to 0x01 (on) or 0x00 (off).")
                infoRow("")
                infoRow("iOS also enables ANCS on the connection so bands with ANCS")
                infoRow("firmware support receive notifications directly from the OS.")
                infoRow("")
                infoRow("Compatible devices:")
                infoRow("  • FitPro-compatible smart bands (Nordic UART)")
                infoRow("  • Any BLE band that supports ANCS GATT (e.g. Galaxy Watch)")
                infoRow("")
                infoRow("Launch the app once to bond. iOS reconnects in the background.")
            }
        }
        .background(Theme.background)
    }

    // MARK: - Row builders

    @ViewBuilder
    private func bondedRow(_ device: BondedDevice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(device.connectionState.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(stateColor(device.connectionState))
            }
            Spacer()
            if device.connectionState == .connected {
                actionButton("Disconnect", color: Theme.dimText) {
                    bt.disconnect(id: device.id)
                }
            }
            actionButton("Remove", color: .red) {
                bt.removeDevice(id: device.id)
            }
        }
        .modifier(RowStyle())
    }

    @ViewBuilder
    private func discoveredRow(_ peripheral: CBPeripheral) -> some View {
        let alreadyBonded = bt.bondedDevices.contains { $0.id == peripheral.identifier }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(peripheral.name ?? "Unknown Device")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
                Text(peripheral.identifier.uuidString.prefix(8).uppercased())
                    .font(.system(size: 10))
                    .foregroundColor(Theme.dimText)
            }
            Spacer()
            if alreadyBonded {
                Text("Bonded")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
            } else {
                Button("Bond") { bt.bond(to: peripheral) }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.accent)
                    .cornerRadius(4)
            }
        }
        .modifier(RowStyle())
    }

    @ViewBuilder
    private func categoryRow(_ category: NotifCategory) -> some View {
        let binding = Binding<Bool>(
            get: { bt.notifCategories[category] ?? true },
            set: { bt.notifCategories[category] = $0 }
        )
        HStack {
            Text(category.rawValue)
                .font(.system(size: 12))
                .foregroundColor(Theme.text)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(Theme.accent)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    // MARK: - Helpers

    private func stateColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected:   return Theme.accent
        case .reconnecting,
             .connecting:  return Color.orange
        case .disconnected: return Theme.dimText
        }
    }

    @ViewBuilder
    private func actionButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(size: 11))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func infoRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Theme.dimText)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
    }
}
