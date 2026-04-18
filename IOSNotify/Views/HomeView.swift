import SwiftUI

struct HomeView: View {
    @ObservedObject private var notifMgr = NotificationManager.shared
    @ObservedObject private var btMgr = BluetoothManager.shared
    @ObservedObject private var appList = AppListManager.shared
    @ObservedObject private var triggerMgr = ShortcutsTriggerManager.shared

    @State private var showRegisterAlert = false

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

                sectionHeader("STEP 1 — DETECT NOTIFICATIONS")

                infoRow(text: "iOS sandboxing prevents reading other apps'")
                infoRow(text: "notifications. Bridge via Shortcuts automation:")
                infoRow(text: "")
                infoRow(text: "  1. Shortcuts → Automation → + → App")
                infoRow(text: "     → select app → Notification Received")
                infoRow(text: "  2. Add action: iOS Notify → Log Notification")
                infoRow(text: "  3. Map Notification Title and Body")
                infoRow(text: "  4. Tap automation → turn off")
                infoRow(text: "     'Ask Before Running'")
                infoRow(text: "  → Notifications now appear in Log tab")

                sectionHeader("STEP 2 — TRIGGER A SHORTCUT")

                infoRow(text: "When a notification arrives, iOS Notify calls")
                infoRow(text: "a Shortcut by name with the notification data.")
                infoRow(text: "Automatic — no taps needed.")
                infoRow(text: "")

                fieldLabel("SHORTCUT NAME")
                TextField("iOS Notify Received", text: Binding(
                    get: { triggerMgr.shortcutName },
                    set: { triggerMgr.shortcutName = $0; triggerMgr.saveSettings() }
                ))
                .textFieldStyle(InlineTextFieldStyle())
                .autocapitalization(.words)

                infoRow(text: "")
                infoRow(text: "The Shortcut receives JSON as text input:")
                infoRow(text: "  {\"app\":\"WhatsApp\",\"title\":\"...\",\"body\":\"...\"}")
                infoRow(text: "")
                infoRow(text: "Setup:")
                infoRow(text: "  1. Create a Shortcut named exactly as above")
                infoRow(text: "  2. Add 'Get Dictionary from Input' action")
                infoRow(text: "  3. Use 'Get Value for Key' to read")
                infoRow(text: "     app / title / body")
                infoRow(text: "  4. Enable 'Shortcut trigger' per app")
                infoRow(text: "     in the Apps tab")

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
        .alert("Close this app now", isPresented: $showRegisterAlert) {
            Button("OK") {}
        } message: {
            Text("A notification will arrive in 5 seconds. Keep iOS Notify in the background so the system registers it as a Shortcuts trigger source.")
        }
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
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
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

struct InlineTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 15))
            .foregroundColor(Theme.text)
            .padding(12)
            .background(Theme.surface)
            .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 16)
    }
}
