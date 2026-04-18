import Foundation
import UIKit
import Combine

struct KnownApp: Identifiable {
    let id: String           // bundle identifier
    let displayName: String
    let urlScheme: String    // used with canOpenURL to detect installation
}

@MainActor
class AppListManager: ObservableObject {
    static let shared = AppListManager()

    // Curated list of popular apps — checked via canOpenURL at scan time.
    // Schemes must also be declared in Info.plist LSApplicationQueriesSchemes.
    static let knownApps: [KnownApp] = [
        KnownApp(id: "net.whatsapp.WhatsApp",          displayName: "WhatsApp",       urlScheme: "whatsapp://send"),
        KnownApp(id: "ph.telegra.Telegraph",            displayName: "Telegram",       urlScheme: "tg://msg"),
        KnownApp(id: "org.whispersystems.signal",       displayName: "Signal",         urlScheme: "sgnl://"),
        KnownApp(id: "com.facebook.Facebook",           displayName: "Facebook",       urlScheme: "fb://"),
        KnownApp(id: "com.facebook.Messenger",          displayName: "Messenger",      urlScheme: "fb-messenger://"),
        KnownApp(id: "com.burbn.instagram",             displayName: "Instagram",      urlScheme: "instagram://"),
        KnownApp(id: "com.burbn.barcelona",             displayName: "Threads",        urlScheme: "barcelona://"),
        KnownApp(id: "com.atebits.Tweetie2",            displayName: "X (Twitter)",    urlScheme: "twitter://"),
        KnownApp(id: "com.hammerandchisel.discord",     displayName: "Discord",        urlScheme: "discord://"),
        KnownApp(id: "com.tinyspeck.chatlyio",          displayName: "Slack",          urlScheme: "slack://"),
        KnownApp(id: "com.toyopagroup.picaboo",         displayName: "Snapchat",       urlScheme: "snapchat://"),
        KnownApp(id: "com.zhiliaoapp.musically",        displayName: "TikTok",         urlScheme: "tiktok://"),
        KnownApp(id: "com.google.Gmail",                displayName: "Gmail",          urlScheme: "googlegmail://"),
        KnownApp(id: "com.microsoft.Office.Outlook",    displayName: "Outlook",        urlScheme: "ms-outlook://"),
        KnownApp(id: "com.linkedin.LinkedIn",           displayName: "LinkedIn",       urlScheme: "linkedin://"),
        KnownApp(id: "com.google.ios.youtube",          displayName: "YouTube",        urlScheme: "youtube://"),
        KnownApp(id: "com.spotify.client",              displayName: "Spotify",        urlScheme: "spotify://"),
        KnownApp(id: "com.viber",                       displayName: "Viber",          urlScheme: "viber://"),
        KnownApp(id: "jp.naver.line",                   displayName: "Line",           urlScheme: "line://"),
        KnownApp(id: "com.tencent.xin",                 displayName: "WeChat",         urlScheme: "weixin://"),
        KnownApp(id: "com.reddit.Reddit",               displayName: "Reddit",         urlScheme: "reddit://"),
        KnownApp(id: "tv.twitch",                       displayName: "Twitch",         urlScheme: "twitch://"),
        KnownApp(id: "pinterest",                       displayName: "Pinterest",      urlScheme: "pinterest://"),
        KnownApp(id: "AlexisBarreyat.BeReal",           displayName: "BeReal",         urlScheme: "bereal://"),
        KnownApp(id: "com.bumble.app",                  displayName: "Bumble",         urlScheme: "bumble://"),
        KnownApp(id: "com.cardify.tinder",              displayName: "Tinder",         urlScheme: "tinder://"),
        KnownApp(id: "com.ubercab.UberClient",          displayName: "Uber",           urlScheme: "uber://"),
        KnownApp(id: "com.zimride.instant",             displayName: "Lyft",           urlScheme: "lyft://"),
        KnownApp(id: "com.skype.skype",                 displayName: "Skype",          urlScheme: "skype://"),
        KnownApp(id: "com.microsoft.teams",             displayName: "Teams",          urlScheme: "msteams://"),
    ]

    @Published var monitoredApps: [MonitoredApp] = []
    @Published var isScanning = false

    private let storageKey = "monitoredApps_v1"

    init() {
        load()
        if monitoredApps.isEmpty {
            scanInstalled()
        }
    }

    // Checks which known apps are installed via URL scheme and pre-populates
    // the list. Existing per-app settings are preserved on re-scan.
    func scanInstalled() {
        isScanning = true
        let detected = Self.knownApps.filter {
            guard let url = URL(string: $0.urlScheme) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
        for known in detected {
            if !monitoredApps.contains(where: { $0.bundleIdentifier == known.id }) {
                monitoredApps.append(MonitoredApp(bundleIdentifier: known.id, displayName: known.displayName))
            }
        }
        isScanning = false
        save()
    }

    func add(bundleId: String, displayName: String) {
        guard !monitoredApps.contains(where: { $0.bundleIdentifier == bundleId }) else { return }
        monitoredApps.append(MonitoredApp(bundleIdentifier: bundleId, displayName: displayName))
        save()
    }

    func remove(id: UUID) {
        monitoredApps.removeAll { $0.id == id }
        save()
    }

    func update(_ app: MonitoredApp) {
        guard let index = monitoredApps.firstIndex(where: { $0.id == app.id }) else { return }
        monitoredApps[index] = app
        save()
    }

    func app(for bundleId: String) -> MonitoredApp? {
        monitoredApps.first { $0.bundleIdentifier == bundleId }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(monitoredApps) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let apps = try? JSONDecoder().decode([MonitoredApp].self, from: data) else { return }
        monitoredApps = apps
    }
}
