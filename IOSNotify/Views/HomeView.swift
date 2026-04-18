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

                if notifMgr.authorizationStatus != .authorized {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider().background(Theme.border)
                        Button("Request notification access") {
                            notifMgr.requestAuthorization()
                        }
                        .buttonStyle(ThemedButtonStyle())
                        .padding(16)
                    }
                }

                sectionHeader("SHORTCUTS SETUP")

                infoRow(text: "1. Tap below to register IOSNotify as a trigger source")
                infoRow(text: "2. Open Shortcuts → Automation → + → Notification Received")
                infoRow(text: "3. Choose IOSNotify as the source app")
                infoRow(text: "4. Filter title containing '[AppName]' for per-app triggers")
                infoRow(text: "5. Add your actions — fires on each forwarded notification")

                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Theme.border)
                    Button("Register as Shortcuts trigger") {
                        notifMgr.sendTestNotification()
                    }
                    .buttonStyle(ThemedButtonStyle(filled: true))
                    .padding(16)
                    .disabled(notifMgr.authorizationStatus != .authorized)
                }

                sectionHeader("RECENT ACTIVITY")

                if notifMgr.recentNotifications.isEmpty {
                    Text("No notifications yet")
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
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(Theme.dimText)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
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
                if n.forwardedToBand {
                    Text("BAND")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.background)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent)
                }
                if n.usedAsShortcutTrigger {
                    Text("SHORTCUT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent, lineWidth: 1))
                }
            }
        }
        .modifier(RowStyle())
        .padding(.vertical, 4)
    }
}
