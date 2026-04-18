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
                VStack(spacing: 8) {
                    Spacer()
                    Text("No diagnostic events")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dimText)
                    Text("Fire a Shortcuts automation to see events here.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dimText)
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
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(entry.tag)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(tagColor(entry.tag))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(tagColor(entry.tag).opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(tagColor(entry.tag), lineWidth: 0.5))
                Spacer()
                Text(Self.dateFormatter.string(from: entry.timestamp))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dimText)
            }
            Text(entry.message)
                .font(.system(size: 12))
                .foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .bottom)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "INTENT":    return Theme.accent
        case "INGEST":    return Color(red: 0.4, green: 0.6, blue: 1.0)
        case "NOTIF":     return Color.orange
        case "LIFECYCLE": return Color.purple
        case "ERROR":     return Color.red
        default:          return Theme.dimText
        }
    }
}
