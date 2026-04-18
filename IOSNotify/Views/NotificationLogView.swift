import SwiftUI

struct NotificationLogView: View {
    @ObservedObject private var notifMgr = NotificationManager.shared
    @State private var filter: FilterMode = .all

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case band = "Band"
        case shortcut = "Shortcut"
    }

    var filtered: [CapturedNotification] {
        switch filter {
        case .all:      return notifMgr.recentNotifications
        case .band:     return notifMgr.recentNotifications.filter { $0.forwardedToBand }
        case .shortcut: return notifMgr.recentNotifications.filter { $0.usedAsShortcutTrigger }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                filterBar
                Divider().frame(width: 1).background(Theme.border)
                Button("Clear") { notifMgr.clearHistory() }
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }
            Divider().background(Theme.border)

            if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text("No notifications")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dimText)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { n in
                            NotifLogRow(notification: n)
                        }
                    }
                }
            }
        }
        .background(Theme.background)
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(FilterMode.allCases, id: \.self) { mode in
                Button(mode.rawValue) {
                    filter = mode
                }
                .font(.system(size: 13, weight: filter == mode ? .semibold : .regular))
                .foregroundColor(filter == mode ? Theme.accent : Theme.dimText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(filter == mode ? Theme.accent : .clear),
                    alignment: .bottom
                )
            }
        }
    }
}

struct NotifLogRow: View {
    let notification: CapturedNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(notification.appName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Spacer()
                Text(notification.timestamp, style: .relative)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dimText)
            }
            if !notification.title.isEmpty {
                Text(notification.title)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
            }
            if !notification.body.isEmpty {
                Text(notification.body)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dimText)
                    .lineLimit(3)
            }
            HStack(spacing: 6) {
                if notification.forwardedToBand {
                    badge("BAND", filled: true)
                }
                if notification.usedAsShortcutTrigger {
                    badge("SHORTCUT", filled: false)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    @ViewBuilder
    private func badge(_ label: String, filled: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(filled ? Theme.background : Theme.accent)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(filled ? Theme.accent : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent, lineWidth: 1))
    }
}
