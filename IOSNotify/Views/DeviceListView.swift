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

                sectionHeader("HOW IT WORKS")

                infoRow("Once bonded, iOS streams all notifications to your device")
                infoRow("via ANCS — the same protocol used by Apple Watch.")
                infoRow("")
                infoRow("Compatible devices:")
                infoRow("  • FitPro-compatible smart bands (Nordic UART / ANCS)")
                infoRow("  • WearOS watches with ANCS support (e.g. Galaxy Watch)")
                infoRow("  • Any BLE wearable that implements the ANCS GATT profile")
                infoRow("")
                infoRow("The app only needs to be launched once to bond. After that,")
                infoRow("iOS handles reconnection and notification streaming in the")
                infoRow("background — no need to keep the app open.")
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
                    .foregroundColor(device.connectionState == .connected ? Theme.accent : Theme.dimText)
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

    // MARK: - Helpers

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
