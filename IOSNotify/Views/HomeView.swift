import SwiftUI

struct HomeView: View {
    @ObservedObject private var notifMgr = NotificationManager.shared
    @ObservedObject private var btMgr = BluetoothManager.shared
    @ObservedObject private var appList = AppListManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                sectionHeader("STATUS")

                statusRow(label: "Notification access",
                          value: notifMgr.authorizationStatus == .authorized ? "Granted" : "Not granted",
                          ok: notifMgr.authorizationStatus == .authorized)
                statusRow(label: "Band connection",
                          value: btMgr.connectionState.rawValue,
                          ok: btMgr.connectionState == .connected)
                statusRow(label: "Monitored apps",
                          value: "\(appList.monitoredApps.count)",
                          ok: !appList.monitoredApps.isEmpty)
                statusRow(label: "Recording",
                          value: notifMgr.isRecording ? "On" : "Off",
                          ok: notifMgr.isRecording)

                if notifMgr.authorizationStatus != .authorized {
                    Divider().background(Theme.border)
                    Button("Request notification access") { notifMgr.requestAuthorization() }
                        .buttonStyle(ThemedButtonStyle())
                        .padding(16)
                }

                sectionHeader("ACTIVITY RECORDING")

                HStack {
                    Text("Record notifications")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { notifMgr.isRecording },
                        set: { notifMgr.setRecording($0) }
                    ))
                    .labelsHidden()
                    .tint(Theme.accent)
                }
                .modifier(RowStyle())

                Divider().background(Theme.border)
                Button("Clear all logs and history") { notifMgr.clearHistory() }
                    .buttonStyle(ThemedButtonStyle())
                    .padding(16)

                sectionHeader("HOW NOTIFICATIONS ARE DETECTED")

                infoRow(text: "iOS sandboxing prevents apps reading other apps'")
                infoRow(text: "notifications. iOS Notify uses two routes:")
                infoRow(text: "")
                infoRow(text: "Route A — Shortcuts action (recommended):")
                infoRow(text: "  1. Shortcuts → Automation → + → App →")
                infoRow(text: "     select any app → Notification Received")
                infoRow(text: "  2. Add action: iOS Notify → Log Notification")
                infoRow(text: "  3. Map Title and Body from the trigger")
                infoRow(text: "  4. Open the automation → disable")
                infoRow(text: "     'Ask Before Running' (runs silently)")
                infoRow(text: "  → Notifications appear in Recent Activity")
                infoRow(text: "")
                infoRow(text: "Route B — iOS Notify as trigger source:")
                infoRow(text: "  1. Tap Register below (one-time)")
                infoRow(text: "  2. iOS Settings → iOS Notify → Notifications")
                infoRow(text: "     → Alert Style: None (hides relay banners)")
                infoRow(text: "  3. Shortcuts → Automation → + →")
                infoRow(text: "     Notification Received → iOS Notify")
                infoRow(text: "  4. Filter title containing [AppName]")
                infoRow(text: "  5. Disable 'Ask Before Running'")

                Divider().background(Theme.border)
                Button("Register as Shortcuts trigger (one-time)") {
                    notifMgr.sendTestNotification()
                }
                .buttonStyle(ThemedButtonStyle(filled: true))
                .padding(16)
                .disabled(notifMgr.authorizationStatus != .authorized)

                sectionHeader("RECENT ACTIVITY")

                if notifMgr.recentNotifications.isEmpty {
                    Text(notifMgr.isRecording ? "No notifications yet" : "Recording is off")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Theme.dimText)
                        .padding(16)
                } else {
                    ForEach(notifMgr.recentNotifications.prefix(5)) { n in
                        notifRow(n)
                    }
                }
            }
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func statusRow(label: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Theme.text)
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(ok ? Theme.accent : Theme.dimText)
        }
        .modifier(RowStyle())
    }

    @ViewBuilder
    private func infoRow(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(Theme.dimText)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func notifRow(_ n: CapturedNotification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(n.appName)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.accent)
                Spacer()
                Text(n.timestamp, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.dimText)
            }
            Text(n.title.isEmpty ? "(no title)" : n.title)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.text)
            if !n.body.isEmpty {
                Text(n.body)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.dimText)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if n.forwardedToBand { badge("BAND", filled: true) }
                if n.usedAsShortcutTrigger { badge("SHORTCUT", filled: false) }
            }
        }
        .modifier(RowStyle())
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func badge(_ label: String, filled: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(filled ? Theme.background : Theme.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(filled ? Theme.accent : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent, lineWidth: 1))
    }
}
