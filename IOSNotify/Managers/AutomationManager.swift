import Foundation
import AVFoundation
import Combine
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
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "notify.wifi.monitor", qos: .utility)
    private var batteryObserver: NSObjectProtocol?
    private var orientationObserver: NSObjectProtocol?
    private var timeTimer: Timer?
    private var btCancellable: AnyCancellable?

    private init() {
        setupBatteryObserver()
        setupOrientationObserver()
        setupWifiMonitor()
        setupBluetoothObserver()
        setupLockStateListener()
        setupTimeTimer()
        reevaluate()
    }

    // MARK: - Public

    func reevaluate() {
        Task {
            // Audio lifecycle is tied to the master enable toggle ONLY.
            // The silent audio loop must run whenever automation is enabled so
            // that Darwin notifications (screen-on) can wake the app from the
            // background regardless of whether any condition is currently met.
            // Conditions exclusively control whether the shortcut fires.
            if config.isEnabled {
                startPersistence()
            } else {
                stopPersistence()
            }
            // Update the UI status indicator (would the shortcut fire right now?).
            conditionsMet = await evaluateConditions()
        }
    }

    /// Call this the first time the Focus condition is enabled in settings.
    func requestFocusAuthorization() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.focusAuthorized = (status == .authorized)
                self?.reevaluate()
            }
        }
    }

    func triggerShortcut() {
        guard let encoded = config.shortcutName
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
        else { return }

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
            // Returns nil when the Focus Status entitlement isn't provisioned;
            // treat nil as "not focused" (condition not met).
            results.append(INFocusStatusCenter.default.focusStatus.isFocused == true)
        }
        if config.wifiEnabled {
            let ssid   = await fetchCurrentSSID()
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
        if config.btDeviceEnabled, let targetID = config.btDeviceID {
            let device = BluetoothManager.shared.bondedDevices.first { $0.id == targetID }
            results.append(device?.connectionState == .connected)
        }

        // No conditions enabled = automation is unconditional: always fire.
        guard !results.isEmpty else { return true }

        switch config.matchStrategy {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains    { $0 }
        }
    }

    // MARK: - Individual condition helpers

    private func isWithinTimeRange() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let cur = minuteOfDay(now,                   cal: cal)
        let s   = minuteOfDay(config.timeRangeStart, cal: cal)
        let e   = minuteOfDay(config.timeRangeEnd,   cal: cal)
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
            player.numberOfLoops = -1
            // Use a barely-audible volume rather than exactly zero.
            // Some iOS versions optimise away true-zero audio, which can
            // allow the system to suspend the playback session unexpectedly.
            player.volume = 0.001
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

    private func silentAudioURL() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notify_silence.wav")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }

        var d = Data()
        func w(_ s: String)   { d.append(contentsOf: s.utf8) }
        func w32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func w16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        let sr: UInt32 = 8000
        let dataLen: UInt32 = sr * 2
        w("RIFF"); w32(36 + dataLen); w("WAVE")
        w("fmt "); w32(16); w16(1); w16(1)
        w32(sr); w32(sr * 2); w16(2); w16(16)
        w("data"); w32(dataLen)
        d.append(Data(count: Int(dataLen)))

        try? d.write(to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Screen-on listener

    private func setupLockStateListener() {
        // NotifyHelper registers for both "com.apple.iokit.hid.displayStatus"
        // (fires on any screen wake, including locked screen) and
        // "com.apple.springboard.lockstate" (fires on unlock).  The two signals
        // together cover every "screen became visible" scenario.
        NotifyHelper.observeScreenOn { [weak self] in
            Task { @MainActor [weak self] in await self?.onScreenTurnedOn() }
        }
    }

    private func onScreenTurnedOn() async {
        guard config.isEnabled else { return }
        // Only fire when the app is in the background (lock screen wake).
        // If the app is active the user is already using the phone, which means
        // the phone is unlocked — wrong scenario.
        guard UIApplication.shared.applicationState != .active else { return }
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
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reevaluate() }
        }
    }

    private func setupOrientationObserver() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reevaluate() }
        }
    }

    private func setupWifiMonitor() {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.reevaluate() }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    private func setupBluetoothObserver() {
        btCancellable = BluetoothManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reevaluate() }
            }
    }

    private func setupTimeTimer() {
        timeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reevaluate() }
        }
    }
}
