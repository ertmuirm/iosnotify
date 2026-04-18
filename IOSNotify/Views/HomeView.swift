import SwiftUI

struct HomeView: View {
    @ObservedObject private var notifMgr = NotificationManager.shared
    @ObservedObject private var btMgr = BluetoothManager.shared
    @ObservedObject private var appList = AppListManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                sectionHeader("STATUS")

                statusRow(label: "Post notifications",
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
                    Button("Grant notification permission") { notifMgr.requestAuthorization() }
                        .buttonStyle(ThemedButtonStyle())
                        .padding(16)
                }

                sectionHeader("ACTIVITY RECORDING")

                HStack {
                    Text("Record notifications")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { notifMgr.isRecording },
                        set: { notifMgr.setRecording($0) }
                    ))
                    .labelsHidden()
                    .tint(Theme.accent)
                    .scaleEffect(0.8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surface)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)

                Divider().background(Theme.border)
                Button("Clear all logs and history") { notifMgr.clearHistory() }
                    .buttonStyle(ThemedButtonStyle())
                    .padding(16)

                sectionHeader("HOW NOTIFICATIONS WORK")

                infoRow(text: "iOS Notify uses ANCS (Apple Notification Center")
                infoRow(text: "Service) — the same protocol used by Apple Watch")
                infoRow(text: "and all BLE smartbands.")
                infoRow(text: "")
                infoRow(text: "Once your band is connected, iOS automatically")
                infoRow(text: "streams every notification directly to the band.")
                infoRow(text: "No Shortcuts or extra setup required.")
                infoRow(text: "")
                infoRow(text: "Steps:")
                infoRow(text: "  1. Go to the Device tab")
                infoRow(text: "  2. Tap 'Scan for bands' and select your band")
                infoRow(text: "  3. Accept the pairing request if prompted")
                infoRow(text: "  → All notifications now appear on the band")

                sectionHeader("RECENT ACTIVITY")

                if notifMgr.recentNotifications.isEmpty {
                    Text(notifMgr.isRecording ? "No notifications yet" : "Recording is off")
                        .font(.system(size: 12))
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
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func statusRow(label: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.text)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(ok ? Theme.accent : Theme.dimText)
        }
        .modifier(RowStyle())
    }

    @ViewBuilder
    private func infoRow(text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Theme.dimText)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func notifRow(_ n: CapturedNotification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(n.appName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Spacer()
                Text(n.timestamp, style: .time)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dimText)
            }
            Text(n.title.isEmpty ? "(no title)" : n.title)
                .font(.system(size: 12))
                .foregroundColor(Theme.text)
            if !n.body.isEmpty {
                Text(n.body)
                    .font(.system(size: 12))
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
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(filled ? Theme.background : Theme.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(filled ? Theme.accent : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent, lineWidth: 1))
    }
}

