import SwiftUI

struct DiagView: View {
    @ObservedObject private var log = DiagnosticLog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(log.entries.count) events")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dimText)
                Spacer()
                Button("Clear") { log.clear() }
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(Theme.border)

            if log.entries.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No events yet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.dimText)
                    Text("iOS blocks direct access to other apps' notifications.\nNotifications reach this app only via a Shortcuts automation:")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dimText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("Shortcuts → Automation → + → App\n→ select Telegram/WhatsApp/etc → Notification Received\n→ add 'Log Notification' action → disable 'Ask Before Running'")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(log.entries) { entry in
                            DiagRow(entry: entry)
                        }
                    }
                }
            }
        }
        .background(Theme.background)
    }
}

struct DiagRow: View {
    let entry: DiagnosticLog.Entry

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.dateFormatter.string(from: entry.timestamp))
                .font(.system(size: 10))
                .foregroundColor(Theme.dimText)
                .fixedSize()
            Text(entry.tag)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(tagColor(entry.tag))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(tagColor(entry.tag).opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(tagColor(entry.tag), lineWidth: 0.5))
                .fixedSize()
            Text(entry.message)
                .font(.system(size: 11))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "INTENT":    return Theme.accent
        case "INGEST":    return Color(red: 0.4, green: 0.6, blue: 1.0)
        case "NOTIF":     return Color.orange
        case "LIFECYCLE": return Theme.dimText
        case "ERROR":     return Color.red
        default:          return Theme.dimText
        }
    }
}
