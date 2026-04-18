import SwiftUI
import CoreBluetooth

struct DeviceView: View {
    @ObservedObject private var bt = BluetoothManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("CONNECTED DEVICE")

                if let device = bt.connectedDevice {
                    connectedRow(device)
                } else {
                    HStack {
                        Text("No device connected")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.dimText)
                        Spacer()
                        Text(bt.connectionState.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(bt.connectionState == .scanning ? Theme.accent : Theme.dimText)
                    }
                    .modifier(RowStyle())
                }

                HStack(spacing: 12) {
                    Button(bt.connectionState == .scanning ? "Stop scan" : "Scan for bands") {
                        if bt.connectionState == .scanning {
                            bt.stopScan()
                        } else {
                            bt.startScan()
                        }
                    }
                    .buttonStyle(ThemedButtonStyle(filled: bt.connectionState != .scanning))

                    if bt.connectedDevice != nil {
                        Button("Disconnect") {
                            bt.disconnect()
                        }
                        .buttonStyle(ThemedButtonStyle())

                        Button("Unbind") {
                            bt.unbind()
                        }
                        .buttonStyle(ThemedButtonStyle())
                    }
                }
                .padding(16)

                if !bt.discoveredDevices.isEmpty {
                    sectionHeader("DISCOVERED DEVICES")
                    ForEach(bt.discoveredDevices, id: \.identifier) { device in
                        deviceRow(device)
                    }
                }

                sectionHeader("PROTOCOL INFO")
                infoRow("Service: 6e400001 (Nordic UART)")
                infoRow("Write (TX): 6e400002")
                infoRow("Notify (RX): 6e400003")
                infoRow("Compatible with FitPro-style bands")
                infoRow("")
                infoRow("If the band doesn't respond, tap Unbind")
                infoRow("to clear the bond, then reconnect.")
            }
        }
        .background(Theme.background)
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
    private func connectedRow(_ device: CBPeripheral) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name ?? "Unknown device")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(device.identifier.uuidString)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dimText)
            }
            Spacer()
            Text("Connected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.accent)
        }
        .modifier(RowStyle())
    }

    @ViewBuilder
    private func deviceRow(_ device: CBPeripheral) -> some View {
        Button {
            bt.connect(to: device)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name ?? "Unknown device")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(device.identifier.uuidString)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dimText)
                }
                Spacer()
                Text("Connect")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
            }
        }
        .modifier(RowStyle())
    }

    @ViewBuilder
    private func infoRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Theme.dimText)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
    }
}
