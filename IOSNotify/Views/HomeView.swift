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

                infoRow(text: "Step 1 — Tap 'Register as trigger' below (one-time)")
                infoRow(text: "Step 2 — iOS Settings → IOSNotify → Notifications")
                infoRow(text: "         → set Alerts to 'None', sound off")
                infoRow(text: "         (IOSNotify still fires Shortcuts silently)")
                infoRow(text: "Step 3 — Shortcuts → Automation → + →")
                infoRow(text: "         Notification Received → IOSNotify")
                infoRow(text: "Step 4 — Filter: title contains '[AppName]'")
                infoRow(text: "         for per-app triggers")
                infoRow(text: "Step 5 — Enable 'Shortcut trigger' per app in Apps tab")

                infoRow(text: "Note: iOS prevents apps from reading other apps'")
                infoRow(text: "notifications directly. IOSNotify delivers a silent")
                infoRow(text: "relay notification — invisible after Step 2 — which")
                infoRow(text: "iOS Shortcuts recognises as its trigger source.")

                VStack(alignment: .leading, spacing: 0) {
                    Divider().background(Theme.border)
                    Button("Register as Shortcuts trigger (one-time)") {
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
