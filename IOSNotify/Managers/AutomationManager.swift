import Foundation
import AVFoundation
import Network
import UIKit
import Intents
import NetworkExtension

// MARK: - AutomationManager

@MainActor
final class AutomationManager: ObservableObject {
    static let shared = AutomationManager()

    @Published var config: AutomationConfig = .load() {
        didSet { config.save(); reevaluate() }
    }
    @Published var isPlayerRunning = false
    @Published var conditionsMet   = false
    @Published var focusAuthorized = false

    private var audioPlayer: AVAudioPlayer?
    private var lockToken: Int32 = -1
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "notify.wifi.monitor", qos: .utility)
    private var batteryObserver: NSObjectProtocol?
    private var orientationObserver: NSObjectProtocol?
    private var timeTimer: Timer?

    private init() {
        setupBatteryObserver()
        setupOrientationObserver()
        setupWifiMonitor()
        setupLockStateListener()
        setupTimeTimer()
        requestFocusAuthorization()
        reevaluate()
    }

    // MARK: - Public

    // Called by settings view after any config mutation that bypasses the didSet
    // (e.g., direct property writes via bindings already trigger didSet).
    func reevaluate() {
        Task {
            let met = await evaluateConditions()
            conditionsMet = met
            met ? startPersistence() : stopPersistence()
        }
    }

    func triggerShortcut() {
        guard let encoded = config.shortcutName
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
        else { return }

        // Wrap in a background task to maximise execution time from suspended state.
        let taskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        UIApplication.shared.open(url, options: [:]) { _ in
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    // MARK: - Condition evaluation

    private func evaluateConditions() async -> Bool {
        guard config.isEnabled else { return false }

        var results: [Bool] = []

        if config.focusEnabled {
            results.append(INFocusStatusCenter.default.focusStatus.isFocused == true)
        }
        if config.wifiEnabled {
            let ssid = await fetchCurrentSSID()
            let target = config.wifiSSID.trimmingCharacters(in: .whitespaces)
            results.append(!target.isEmpty && ssid?.lowercased() == target.lowercased())
        }
        if config.chargingEnabled {
            let s = UIDevice.current.batteryState
            results.append(s == .charging || s == .full)
        }
        if config.timeRangeEnabled {
            results.append(isWithinTimeRange())
        }
        if config.orientationEnabled {
            results.append(matchesOrientation())
        }

        guard !results.isEmpty else { return false }

        switch config.matchStrategy {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains    { $0 }
        }
    }

    // MARK: - Individual condition checks

    private func isWithinTimeRange() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let cur = minuteOfDay(now,     cal: cal)
        let s   = minuteOfDay(config.timeRangeStart, cal: cal)
        let e   = minuteOfDay(config.timeRangeEnd,   cal: cal)
        // Handle overnight ranges (e.g. 22:00 – 08:00)
        return s <= e ? (cur >= s && cur < e) : (cur >= s || cur < e)
    }

    private func minuteOfDay(_ date: Date, cal: Calendar) -> Int {
        cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private func matchesOrientation() -> Bool {
        let o = UIDevice.current.orientation
        switch config.targetOrientation {
        case .portrait:       return o == .portrait
        case .landscapeLeft:  return o == .landscapeLeft
        case .landscapeRight: return o == .landscapeRight
        case .faceUp:         return o == .faceUp
        case .faceDown:       return o == .faceDown
        }
    }

    private func fetchCurrentSSID() async -> String? {
        await withCheckedContinuation { cont in
            NEHotspotNetwork.fetchCurrent { cont.resume(returning: $0?.ssid) }
        }
    }

    // MARK: - Background persistence (silent audio loop)

    private func startPersistence() {
        guard !isPlayerRunning, let url = silentAudioURL() else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // loop forever
            player.volume = 0           // truly silent
            player.play()
            audioPlayer = player
            isPlayerRunning = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        } catch {
            isPlayerRunning = false
        }
    }

    private func stopPersistence() {
        guard isPlayerRunning else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        isPlayerRunning = false
    }

    // Generates a 1-second mono 8 kHz silent WAV in the temp directory.
    private func silentAudioURL() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notify_silence.wav")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }

        var d = Data()
        func w(_ s: String)   { d.append(contentsOf: s.utf8) }
        func w32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func w16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        let sr: UInt32  = 8000          // 8 kHz, mono, 16-bit
        let dataLen: UInt32 = sr * 2    // 1 second × 2 bytes/sample
        w("RIFF"); w32(36 + dataLen); w("WAVE")
        w("fmt "); w32(16); w16(1); w16(1)      // PCM, 1 ch
        w32(sr); w32(sr * 2); w16(2); w16(16)   // byte rates, block align, bps
        w("data"); w32(dataLen)
        d.append(Data(count: Int(dataLen)))     // silence

        try? d.write(to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Darwin lock-state listener

    private func setupLockStateListener() {
        // state == 0: display turning ON  |  state == 1: display turning OFF / locked
        var token: Int32 = -1
        notify_register_dispatch(
            "com.apple.springboard.lockstate",
            &token,
            DispatchQueue.main
        ) { [weak self] tok in
            var state: UInt64 = 0
            notify_get_state(tok, &state)
            if state == 0 {
                Task { @MainActor [weak self] in await self?.onScreenTurnedOn() }
            }
        }
        lockToken = token
    }

    private func onScreenTurnedOn() async {
        let met = await evaluateConditions()
        guard met else { return }
        triggerShortcut()
    }

    // MARK: - Environment observers

    private func setupBatteryObserver() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reevaluate() }
    }

    private func setupOrientationObserver() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reevaluate() }
    }

    private func setupWifiMonitor() {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.reevaluate() }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    private func setupTimeTimer() {
        // Re-evaluate every 60 s so time-range transitions are caught promptly.
        timeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reevaluate()
        }
    }

    // MARK: - Focus authorization

    private func requestFocusAuthorization() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.focusAuthorized = (status == .authorized)
            }
        }
    }
}
