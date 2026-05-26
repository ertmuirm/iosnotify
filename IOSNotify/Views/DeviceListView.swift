import SwiftUI
import CoreBluetooth

struct DeviceListView: View {
    @ObservedObject private var bt = BluetoothManager.shared
    @State private var expandedDeviceId: UUID? = nil

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
                        if expandedDeviceId == device.id {
                            deviceSettingsPanel(device)
                        }
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

                toggleRow(
                    label: "Auto-reconnect",
                    subtitle: "Reconnect in the background if a bonded device drops",
                    isOn: $bt.autoReconnect
                )

                sectionHeader("ANCS SETUP")

                infoRow("Hryfine / L13 — two pairings required:")
                infoRow("")
                infoRow("Step 1 (BLE data link — do this first)")
                infoRow("• Use the SCAN section above to find your band")
                infoRow("• Tap Bond — the app connects and sends the init sequence")
                infoRow("")
                infoRow("Step 2 (Classic BT system bond — for notifications)")
                infoRow("• Open iOS Settings → Bluetooth")
                infoRow("• Look for a second entry named \"Hry3.0\" or \"Hryf BT\"")
                infoRow("• Tap it to pair — iOS will show a pairing dialog")
                infoRow("• After pairing, a ⓘ icon appears next to the entry")
                infoRow("• Tap ⓘ and enable \"Share System Notifications\"")
                infoRow("")
                infoRow("The Notify app manages the BLE data link (Step 1).")
                infoRow("The Classic BT entry (Step 2) is what enables iOS")
                infoRow("notification forwarding to the band.")
                infoRow("")
                infoRow("Generic ANCS devices:")
                infoRow("• Bond in this app, then open iOS Settings → Bluetooth")
                infoRow("• Find your device, tap ⓘ, enable \"Share System Notifications\"")
            }
        }
        .background(Theme.background)
    }

    // MARK: - Bonded device row

    @ViewBuilder
    private func bondedRow(_ device: BondedDevice) -> some View {
        let isExpanded = expandedDeviceId == device.id
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.text)
                HStack(spacing: 6) {
                    Text(device.connectionState.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(stateColor(device.connectionState))
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.dimText)
                    Text(device.deviceType.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.dimText)
                }
            }
            Spacer()
            if device.connectionState == .connected {
                actionButton("Disconnect", color: Theme.dimText) {
                    bt.disconnect(id: device.id)
                }
            }
            actionButton("Remove", color: Theme.dimText) {
                bt.removeDevice(id: device.id)
            }
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10))
                .foregroundColor(Theme.dimText)
        }
        .modifier(RowStyle())
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedDeviceId = isExpanded ? nil : device.id
            }
        }
    }

    // MARK: - Per-device settings panel

    @ViewBuilder
    private func deviceSettingsPanel(_ device: BondedDevice) -> some View {
        VStack(spacing: 0) {

            // Device type picker
            HStack {
                Text("Device type")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
                Spacer()
                Picker("", selection: Binding(
                    get: { device.deviceType },
                    set: { bt.setDeviceType($0, for: device.id) }
                )) {
                    ForEach(DeviceType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                .font(.system(size: 12))
            }
            .settingsRow()

            if device.deviceType != .genericAncs {

                // Vibration level slider
                HStack(spacing: 12) {
                    Text("Vibration")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text)
                    Slider(
                        value: Binding<Double>(
                            get: { Double(device.vibrationLevel) },
                            set: { bt.setVibrationLevel(Int($0.rounded()), for: device.id) }
                        ),
                        in: 0...3, step: 1
                    )
                    .tint(Theme.accent)
                    Text(vibrationLabel(device.vibrationLevel))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.dimText)
                        .frame(width: 36, alignment: .trailing)
                }
                .settingsRow()

                // Find device button (only when connected)
                if device.connectionState == .connected {
                    Button {
                        bt.findDevice(id: device.id)
                    } label: {
                        HStack {
                            Text("Find Device")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text)
                            Spacer()
                            Text("Vibrates 5 s →")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.accent)
                        }
                        .settingsRow()
                    }
                }
            }

            if device.deviceType == .hryfine {
                Text("Uses the AB-header (L13) protocol. Time sync, vibration level, and notification category mask are sent on every connection.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.dimText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.surface.opacity(0.6))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
            }
        }
    }

    // MARK: - Discovered device row

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

    // MARK: - Notification category row

    @ViewBuilder
    private func categoryRow(_ category: NotifCategory) -> some View {
        toggleRow(
            label: category.rawValue,
            isOn: Binding(
                get: { bt.notifCategories[category] ?? true },
                set: { bt.notifCategories[category] = $0 }
            )
        )
    }

    // MARK: - Generic toggle row

    @ViewBuilder
    private func toggleRow(label: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            if let sub = subtitle {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 12)).foregroundColor(Theme.text)
                    Text(sub).font(.system(size: 11)).foregroundColor(Theme.dimText)
                }
            } else {
                Text(label).font(.system(size: 12)).foregroundColor(Theme.text)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent).scaleEffect(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, subtitle != nil ? 8 : 6)
        .background(Theme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    // MARK: - Helpers

    private func vibrationLabel(_ level: Int) -> String {
        switch level { case 0: return "Off"; case 1: return "Low"; case 2: return "Med"; default: return "High" }
    }

    private func stateColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected:            return Theme.accent
        case .reconnecting,
             .connecting:          return Theme.text
        case .disconnected:         return Theme.dimText
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

// MARK: - Settings row style helper

private extension View {
    func settingsRow() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.surface.opacity(0.6))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }
}
