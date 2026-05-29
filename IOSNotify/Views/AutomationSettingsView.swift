import SwiftUI

struct AutomationSettingsView: View {
    @ObservedObject private var mgr = AutomationManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ───────────────────────────────────────────────
                HStack {
                    Text("Screen Automation")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Theme.surface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)

                // ── Master enable ─────────────────────────────────────────
                sectionHeader("AUTOMATION")

                toggleRow(
                    label: "Screen-On Automation",
                    subtitle: "Run shortcut when the display turns on",
                    isOn: $mgr.config.isEnabled
                )

                if mgr.config.isEnabled {
                    // Shortcut name
                    HStack {
                        Text("Shortcut Name")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                        Spacer()
                        TextField("Display On", text: $mgr.config.shortcutName)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.accent)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .settingsRow()

                    // Status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(mgr.isPlayerRunning ? Theme.accent : Theme.dimText)
                            .frame(width: 6, height: 6)
                        Text(mgr.isPlayerRunning
                             ? "Background engine active — conditions met"
                             : "Background engine idle — conditions not met")
                            .font(.system(size: 11))
                            .foregroundColor(mgr.isPlayerRunning ? Theme.accent : Theme.dimText)
                        Spacer()
                    }
                    .settingsRow()
                }

                // ── Match strategy ────────────────────────────────────────
                if mgr.config.isEnabled {
                    sectionHeader("MATCH STRATEGY")

                    HStack {
                        Text("Logic")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Picker("", selection: $mgr.config.matchStrategy) {
                            ForEach(MatchStrategy.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                        .font(.system(size: 12))
                    }
                    .settingsRow()

                    infoRow(mgr.config.matchStrategy == .all
                        ? "All enabled conditions must be true simultaneously."
                        : "At least one enabled condition must be true.")

                    // ── Conditions ────────────────────────────────────────
                    sectionHeader("CONDITIONS")

                    // 1 · Focus / DND
                    conditionBlock(
                        toggle: $mgr.config.focusEnabled,
                        label: "Focus / Do Not Disturb",
                        subtitle: "Only run while any Focus or DND mode is active"
                    ) {
                        if !mgr.focusAuthorized {
                            infoRow("Focus status access not authorized. Open Settings → Privacy → Focus.")
                        }
                    }

                    // 2 · Wi-Fi SSID
                    conditionBlock(
                        toggle: $mgr.config.wifiEnabled,
                        label: "Wi-Fi Network",
                        subtitle: "Only run when connected to a specific network"
                    ) {
                        HStack {
                            Text("SSID")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text)
                            Spacer()
                            TextField("Network name", text: $mgr.config.wifiSSID)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.accent)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .settingsRow()
                    }

                    // 3 · Charging
                    conditionBlock(
                        toggle: $mgr.config.chargingEnabled,
                        label: "Charging",
                        subtitle: "Only run while the device is plugged in"
                    ) { EmptyView() }

                    // 4 · Time range
                    conditionBlock(
                        toggle: $mgr.config.timeRangeEnabled,
                        label: "Time Range",
                        subtitle: "Only run within a specified time window"
                    ) {
                        HStack {
                            Text("From")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text)
                            Spacer()
                            DatePicker("", selection: $mgr.config.timeRangeStart,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .tint(Theme.accent)
                        }
                        .settingsRow()

                        HStack {
                            Text("To")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text)
                            Spacer()
                            DatePicker("", selection: $mgr.config.timeRangeEnd,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .tint(Theme.accent)
                        }
                        .settingsRow()

                        infoRow("Overnight ranges (e.g. 22:00 → 08:00) are supported.")
                    }

                    // 5 · Orientation
                    conditionBlock(
                        toggle: $mgr.config.orientationEnabled,
                        label: "Device Orientation",
                        subtitle: "Only run when the device is in a specific orientation"
                    ) {
                        HStack {
                            Text("Orientation")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text)
                            Spacer()
                            Picker("", selection: $mgr.config.targetOrientation) {
                                ForEach(TargetOrientation.allCases) { o in
                                    Text(o.rawValue).tag(o)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.accent)
                            .font(.system(size: 12))
                        }
                        .settingsRow()
                    }
                }

                // ── Setup notes ───────────────────────────────────────────
                sectionHeader("SETUP NOTES")

                infoRow("1. Create a Shortcut named exactly as entered above.")
                infoRow("2. Enable \"Allow Running Shortcuts\" in Settings → Shortcuts.")
                infoRow("3. The background engine only runs while conditions are met,")
                infoRow("   preserving battery when idle.")
                infoRow("4. Wi-Fi SSID access requires the Wi-Fi Information entitlement")
                infoRow("   (provisioning profile). SSID returns nil in Simulator.")
                infoRow("5. Focus status requires the Focus Status entitlement and")
                infoRow("   authorization from the user.")

                Spacer(minLength: 40)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Reusable sub-views

    @ViewBuilder
    private func conditionBlock<Detail: View>(
        toggle: Binding<Bool>,
        label: String,
        subtitle: String,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        toggleRow(label: label, subtitle: subtitle, isOn: toggle)
        if toggle.wrappedValue {
            detail()
        }
    }

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
