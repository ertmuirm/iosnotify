import Foundation
import CoreBluetooth

// MARK: - Device type

enum DeviceType: String, Codable, CaseIterable, Identifiable {
    case fitpro      = "FitPro / compatible"
    case hryfine     = "Hryfine / L13"
    case genericAncs = "Generic (ANCS only)"
    var id: String { rawValue }
    var sendsInitSequence: Bool { self != .genericAncs }
    var requiresANCS: Bool { self != .fitpro }
}

// MARK: - Notification categories

enum NotifCategory: String, CaseIterable, Codable, Identifiable {
    case sms      = "Messages / SMS"
    case calls    = "Phone Calls"
    case wechat   = "WeChat"
    case qq       = "QQ"
    case facebook = "Facebook / Messenger"
    case twitter  = "Twitter / X"
    case line     = "Line"
    case whatsapp = "WhatsApp"
    case outlook  = "Outlook"
    case email    = "Email"
    case generic  = "Other"

    var id: String { rawValue }

    var payloadIndex: Int {
        switch self {
        case .sms: return 0; case .calls: return 1; case .qq: return 2
        case .wechat: return 3; case .facebook: return 4; case .twitter: return 5
        case .line: return 6; case .whatsapp: return 7; case .outlook: return 8
        case .email: return 9; case .generic: return 10
        }
    }

    var l13Bit: UInt32 {
        switch self {
        case .calls: return 0x00000001; case .sms: return 0x00000002
        case .wechat: return 0x00000004; case .qq: return 0x00000008
        case .facebook: return 0x00000010; case .twitter: return 0x00000020
        case .whatsapp: return 0x00000040; case .outlook: return 0x00000080
        case .email: return 0x00000100; case .line: return 0x00000200
        case .generic: return 0x00000400
        }
    }
}

// MARK: - HryFine / L13 GATT constants
//
// The L13 uses a Realtek RTL8762DT chip (NOT Nordic NUS stack).
// Service and characteristic UUIDs below are easily swappable per firmware version.
//
// Required Info.plist keys for BLE background execution:
//   NSBluetoothAlwaysUsageDescription  — usage string
//   UIBackgroundModes                  — bluetooth-central
//   UIRequiredDeviceCapabilities       — bluetooth-le

private enum HryFine {
    // Primary service candidates — firmware versions vary on short vs. full UUID
    static let serviceUUID_3802 = CBUUID(string: "3802")
    static let serviceUUID_FFE0 = CBUUID(string: "FFE0")
    static let serviceUUID_FEE7 = CBUUID(string: "0000FEE7-0000-1000-8000-00805F9B34FB")

    // Write+Notify char candidates for the primary pairing channel
    static let charUUID_3803 = CBUUID(string: "3803")
    static let charUUID_FFE1 = CBUUID(string: "FFE1")

    // Legacy FEE7-path chars (RTL8762DT firmware variant)
    static let txCharUUID = CBUUID(string: "000036F6-0000-1000-8000-00805F9B34FB") // phone → watch
    static let rxCharUUID = CBUUID(string: "000036F5-0000-1000-8000-00805F9B34FB") // watch → phone

    // All write-target char UUIDs across firmware variants
    static let commandCharUUIDs: Set<CBUUID> = [charUUID_3803, charUUID_FFE1, txCharUUID]

    // Forces peripheral to demand an encrypted link → iOS shows Bluetooth Pairing Request dialog
    static let ancsActivationPacket = Data([0xAB, 0x00, 0x04, 0xFF, 0x21, 0x01, 0x01])
    // Fallback handshake for FEE7/36F6 firmware path
    static let handshakePacket      = Data([0xAB, 0x03, 0x01, 0x00, 0xAF])
}

// MARK: - ANCS service (hosted by iOS, may be proxied by firmware post-bonding)

private enum ANCSService {
    static let serviceUUID            = CBUUID(string: "7905F431-B5CE-4E99-A40F-4B1E122D00D0")
    static let notificationSourceUUID = CBUUID(string: "9FBF120D-6301-42D9-8C58-25E699A21DBD")
}

// MARK: - Nordic UART Service (FitPro-compatible, two UUID suffix variants)

private enum NUS {
    static let txChar_v1 = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9d")
    static let txChar_v2 = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    static let rxChar_v1 = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9d")
    static let rxChar_v2 = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    static let txCharUUIDs: Set<CBUUID> = [txChar_v1, txChar_v2]
    static let rxCharUUIDs: Set<CBUUID> = [rxChar_v1, rxChar_v2]
    // FitPro advertises this service UUID during scanning
    static let serviceUUID_v1 = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9D")
}

// MARK: - FitPro BLE protocol (CD-header, Nordic UART)

private enum FitPro {
    static let GROUP_GENERAL:      UInt8 = 0x12
    static let GROUP_REQUEST_DATA: UInt8 = 0x1A
    static let GROUP_BAND_INFO:    UInt8 = 0x20
    static let GROUP_BIND:         UInt8 = 0x14

    static func packet(group: UInt8, cmd: UInt8, payload: [UInt8] = []) -> Data {
        let pLen = payload.count
        let fLen = 5 + pLen
        var b: [UInt8] = [0xCD,
                          UInt8((fLen >> 8) & 0xFF), UInt8(fLen & 0xFF),
                          group, 0x01, cmd,
                          UInt8((pLen >> 8) & 0xFF), UInt8(pLen & 0xFF)]
        b += payload
        return Data(b)
    }

    static func notificationsEnablePacket(enabled: [NotifCategory: Bool]) -> Data {
        var payload = [UInt8](repeating: 0x01, count: 11)
        for (cat, on) in enabled { payload[cat.payloadIndex] = on ? 0x01 : 0x00 }
        return packet(group: GROUP_GENERAL, cmd: 0x07, payload: payload)
    }

    static func vibrationPacket(level: Int) -> Data {
        let p: [UInt8]
        switch level {
        case 0:  p = [0x00, 0x00, 0x00, 0x00]
        case 1:  p = [0x01, 0x01, 0x00, 0x00]
        case 2:  p = [0x01, 0x01, 0x01, 0x00]
        default: p = [0x01, 0x01, 0x01, 0x01]
        }
        return packet(group: GROUP_GENERAL, cmd: 0x08, payload: p)
    }

    static func findBandPacket(start: Bool) -> Data {
        packet(group: GROUP_GENERAL, cmd: 0x0B, payload: [start ? 0x01 : 0x00])
    }
}

// MARK: - L13 BLE protocol (AB-header, sent via HryFine.txCharUUID = 36F6)
//
// Frame: AB 00 [LEN] [CAT] [CMD] [PAYLOAD...]
// LEN = bytes from CAT to end. Packets with 4+ payload bytes append XOR checksum.

private enum L13 {
    static func packet(cat: UInt8, cmd: UInt8, payload: [UInt8] = []) -> Data {
        let dataBytes: [UInt8] = [cat, cmd] + payload
        let needsChecksum = payload.count >= 4
        let len = UInt8(dataBytes.count + (needsChecksum ? 1 : 0))
        var result: [UInt8] = [0xAB, 0x00, len] + dataBytes
        if needsChecksum { result.append(dataBytes.reduce(0, ^)) }
        return Data(result)
    }

    static func notificationsPacket(enabled: [NotifCategory: Bool]) -> Data {
        var mask: UInt32 = 0
        for (cat, on) in enabled where on { mask |= cat.l13Bit }
        return packet(cat: 0x02, cmd: 0x01, payload: [
            UInt8((mask >> 24) & 0xFF), UInt8((mask >> 16) & 0xFF),
            UInt8((mask >>  8) & 0xFF), UInt8( mask        & 0xFF)
        ])
    }

    static func vibrationPacket(level: Int) -> Data {
        let (intensity, repeats): (UInt8, UInt8)
        switch level {
        case 0:  (intensity, repeats) = (0x00, 0x00)
        case 1:  (intensity, repeats) = (0x01, 0x01)
        case 2:  (intensity, repeats) = (0x02, 0x02)
        default: (intensity, repeats) = (0x03, 0x03)
        }
        return packet(cat: 0x04, cmd: 0x02, payload: [intensity, repeats])
    }

    static func findBandPacket(start: Bool) -> Data {
        packet(cat: 0x03, cmd: 0x01, payload: [start ? 0x01 : 0x00])
    }

    static func timeSyncPacket() -> Data {
        let c = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date())
        let y = c.year ?? 2026
        return packet(cat: 0x01, cmd: 0x01, payload: [
            UInt8((y >> 8) & 0xFF), UInt8(y & 0xFF),
            UInt8(c.month  ?? 1), UInt8(c.day    ?? 1),
            UInt8(c.hour   ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0)
        ])
    }
}

// MARK: - Device model

enum ConnectionState: String, Codable {
    case disconnected  = "Disconnected"
    case connecting    = "Connecting…"
    case connected     = "Connected"
    case reconnecting  = "Reconnecting…"
}

struct BondedDevice: Identifiable, Codable {
    let id: UUID
    let name: String
    var deviceType: DeviceType = .genericAncs
    var vibrationLevel: Int    = 3
    var connectionState: ConnectionState = .disconnected

    private enum CodingKeys: String, CodingKey {
        case id, name, deviceType, vibrationLevel
    }
}

// MARK: - BluetoothManager

class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published var bondedDevices: [BondedDevice] = []
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: autoReconnectKey) }
    }
    @Published var notifCategories: [NotifCategory: Bool] {
        didSet { saveCategories(); resendNotifEnable() }
    }
    // L13 sensor data streamed from 36F5 notify characteristic
    @Published var heartRate: Int    = 0
    @Published var stepCount: Int    = 0
    @Published var batteryLevel: Int = 0

    private var central: CBCentralManager!
    private var activePeripherals:  [UUID: CBPeripheral]     = [:]
    private var writeChars:         [UUID: CBCharacteristic] = [:]
    private var pendingDeviceTypes: [UUID: DeviceType]       = [:]

    private let storageKey       = "bondedDevices_v1"
    private let autoReconnectKey = "autoReconnect_v1"
    private let categoriesKey    = "notifCategories_v1"

    private func connectOptions(for type: DeviceType) -> [String: Any] {
        switch type {
        case .hryfine, .genericAncs:
            // RequiresANCS: (1) enables "Share System Notifications" toggle after bonding,
            // (2) combined with encrypted characteristic access triggers the pairing dialog.
            return [CBConnectPeripheralOptionRequiresANCS: true]
        case .fitpro:
            return [:]
        }
    }

    private func detectDeviceType(from name: String?) -> DeviceType {
        let n = name?.lowercased() ?? ""
        if n.contains("hryfine") || n.contains("hryf") || n == "l13"
            || n.contains("watch") { return .hryfine }
        if n.contains("fitpro") || n.contains("fit pro") { return .fitpro }
        return .genericAncs
    }

    override init() {
        autoReconnect   = UserDefaults.standard.object(forKey: "autoReconnect_v1") as? Bool ?? true
        notifCategories = Self.loadCategories()
        super.init()
        loadBonded()
        // queue: nil → callbacks on main thread, eliminating data races on @Published state.
        // RestoreIdentifierKey: iOS silently re-launches the app in the background after a
        // reboot to restore the central manager and resume pending connections.
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "L13WatchRestorer"]
        )
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        discoveredDevices = []
        isScanning = true
        // withServices: nil — many devices (including L13) don't advertise service UUIDs
        // in their ad packets, so a service filter would miss them entirely.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.stopScan() }
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func bond(to peripheral: CBPeripheral) {
        stopScan()
        let type = pendingDeviceTypes[peripheral.identifier]
                   ?? detectDeviceType(from: peripheral.name)
        pendingDeviceTypes[peripheral.identifier] = type
        setConnectionState(peripheral.identifier, .connecting)
        central.connect(peripheral, options: connectOptions(for: type))
    }

    func disconnect(id: UUID) {
        guard let p = activePeripherals[id] else { return }
        central.cancelPeripheralConnection(p)
    }

    func removeDevice(id: UUID) {
        disconnect(id: id)
        bondedDevices.removeAll { $0.id == id }
        activePeripherals.removeValue(forKey: id)
        writeChars.removeValue(forKey: id)
        saveBonded()
    }

    func setDeviceType(_ type: DeviceType, for id: UUID) {
        guard let idx = bondedDevices.firstIndex(where: { $0.id == id }) else { return }
        bondedDevices[idx].deviceType = type
        saveBonded()
    }

    func setVibrationLevel(_ level: Int, for id: UUID) {
        guard let idx = bondedDevices.firstIndex(where: { $0.id == id }) else { return }
        bondedDevices[idx].vibrationLevel = max(0, min(3, level))
        saveBonded()
        guard let char = writeChars[id],
              let p = activePeripherals[id], p.state == .connected else { return }
        let pkt: Data
        switch bondedDevices[idx].deviceType {
        case .hryfine:     pkt = L13.vibrationPacket(level: bondedDevices[idx].vibrationLevel)
        case .fitpro:      pkt = FitPro.vibrationPacket(level: bondedDevices[idx].vibrationLevel)
        case .genericAncs: return
        }
        write(pkt, to: p, characteristic: char)
    }

    func findDevice(id: UUID) {
        guard let char = writeChars[id],
              let p = activePeripherals[id], p.state == .connected else { return }
        let (start, stop): (Data, Data)
        switch deviceType(for: id) {
        case .hryfine: (start, stop) = (L13.findBandPacket(start: true),    L13.findBandPacket(start: false))
        default:       (start, stop) = (FitPro.findBandPacket(start: true), FitPro.findBandPacket(start: false))
        }
        write(start, to: p, characteristic: char)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self,
                  let char = self.writeChars[id],
                  let p = self.activePeripherals[id], p.state == .connected else { return }
            self.write(stop, to: p, characteristic: char)
        }
    }

    // MARK: - Private

    // Must be called on the main queue (modifies @Published bondedDevices).
    private func setConnectionState(_ id: UUID, _ state: ConnectionState) {
        guard let idx = bondedDevices.firstIndex(where: { $0.id == id }) else { return }
        bondedDevices[idx].connectionState = state
    }

    private func deviceType(for id: UUID) -> DeviceType {
        bondedDevices.first(where: { $0.id == id })?.deviceType ?? .genericAncs
    }

    private func reconnectAll() {
        let uuids = bondedDevices.map { $0.id }
        guard !uuids.isEmpty else { return }
        for p in central.retrievePeripherals(withIdentifiers: uuids) {
            setConnectionState(p.identifier, .connecting)
            central.connect(p, options: connectOptions(for: deviceType(for: p.identifier)))
        }
    }

    private func scheduleReconnect(for peripheral: CBPeripheral) {
        guard autoReconnect,
              bondedDevices.contains(where: { $0.id == peripheral.identifier }) else { return }
        setConnectionState(peripheral.identifier, .reconnecting)
        // iOS connection requests never time out — calling connect once keeps iOS watching
        // for the device's address forever and wakes the app as soon as it's in range.
        central.connect(peripheral,
                        options: connectOptions(for: deviceType(for: peripheral.identifier)))
    }

    // Chunks payloads >20 bytes; uses .withResponse when the characteristic supports it
    // so auth-gated writes surface ATT_ERR_INSUFFICIENT_AUTHEN → iOS pairing dialog.
    private func write(_ data: Data, to peripheral: CBPeripheral,
                       characteristic: CBCharacteristic) {
        if data.count > 20 {
            var offset = data.startIndex
            while offset < data.endIndex {
                let end = data.index(offset, offsetBy: 20, limitedBy: data.endIndex) ?? data.endIndex
                peripheral.writeValue(data[offset..<end], for: characteristic, type: .withoutResponse)
                offset = end
            }
        } else {
            let type: CBCharacteristicWriteType =
                characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(data, for: characteristic, type: type)
        }
    }

    private func sendInitSequence(to peripheral: CBPeripheral, char: CBCharacteristic) {
        switch deviceType(for: peripheral.identifier) {
        case .fitpro:      sendFitProInit(to: peripheral, char: char)
        case .hryfine:     sendL13Init(to: peripheral, char: char)
        case .genericAncs: break
        }
    }

    private func sendFitProInit(to peripheral: CBPeripheral, char: CBCharacteristic) {
        var t: TimeInterval = 0.05
        func send(_ data: Data, gap: TimeInterval = 0.2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self, weak peripheral] in
                guard let self, let p = peripheral, p.state == .connected else { return }
                self.write(data, to: p, characteristic: char)
            }
            t += gap
        }
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0x0A, payload: [0x02]))
        let ts = UInt32(Date().timeIntervalSince1970)
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0x01, payload: [
            UInt8((ts >> 24) & 0xFF), UInt8((ts >> 16) & 0xFF),
            UInt8((ts >>  8) & 0xFF), UInt8( ts        & 0xFF)
        ]))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x0A))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x0C))
        send(FitPro.packet(group: FitPro.GROUP_GENERAL,      cmd: 0x15, payload: [0x00]))
        send(FitPro.packet(group: FitPro.GROUP_GENERAL,      cmd: 0xFF, payload: [0x01]))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x01))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x0F))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x10))
        send(FitPro.packet(group: FitPro.GROUP_BAND_INFO,    cmd: 0x02))
        let vib = bondedDevices.first(where: { $0.id == peripheral.identifier })?.vibrationLevel ?? 3
        send(FitPro.vibrationPacket(level: vib))
        send(FitPro.notificationsEnablePacket(enabled: notifCategories))
    }

    private func sendL13Init(to peripheral: CBPeripheral, char: CBCharacteristic) {
        let wType: CBCharacteristicWriteType =
            char.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(HryFine.handshakePacket, for: char, type: wType)
        sendL13Config(to: peripheral, delay: 2.5)
    }

    // Sends time sync + vibration level + notification mask via the stored writeChar.
    // Called after handshake (FEE7/36F6 path) or after ANCS activation (3803/FFE1 path).
    private func sendL13Config(to peripheral: CBPeripheral, delay: TimeInterval) {
        let id = peripheral.identifier
        var t = delay
        func sched(_ data: Data) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self, weak peripheral] in
                guard let self, let p = peripheral, p.state == .connected,
                      let c = self.writeChars[id] else { return }
                self.write(data, to: p, characteristic: c)
            }
            t += 0.2
        }
        sched(L13.timeSyncPacket())
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self, weak peripheral] in
            guard let self, let p = peripheral, p.state == .connected,
                  let c = self.writeChars[id] else { return }
            let vib = self.bondedDevices.first(where: { $0.id == id })?.vibrationLevel ?? 3
            self.write(L13.vibrationPacket(level: vib), to: p, characteristic: c)
        }
        t += 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self, weak peripheral] in
            guard let self, let p = peripheral, p.state == .connected,
                  let c = self.writeChars[id] else { return }
            self.write(L13.notificationsPacket(enabled: self.notifCategories), to: p, characteristic: c)
        }
    }

    private func resendNotifEnable() {
        for (id, char) in writeChars {
            guard let p = activePeripherals[id], p.state == .connected else { continue }
            let pkt: Data
            switch deviceType(for: id) {
            case .fitpro:      pkt = FitPro.notificationsEnablePacket(enabled: notifCategories)
            case .hryfine:     pkt = L13.notificationsPacket(enabled: notifCategories)
            case .genericAncs: continue
            }
            write(pkt, to: p, characteristic: char)
        }
    }

    // MARK: - Persistence

    private func saveBonded() {
        if let data = try? JSONEncoder().encode(bondedDevices) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadBonded() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let devices = try? JSONDecoder().decode([BondedDevice].self, from: data) else { return }
        bondedDevices = devices
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(notifCategories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
    }

    private static func loadCategories() -> [NotifCategory: Bool] {
        if let data = UserDefaults.standard.data(forKey: "notifCategories_v1"),
           let cats = try? JSONDecoder().decode([NotifCategory: Bool].self, from: data) {
            return cats
        }
        return Dictionary(uniqueKeysWithValues: NotifCategory.allCases.map { ($0, true) })
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn { reconnectAll() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in peripherals { activePeripherals[p.identifier] = p; p.delegate = self }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = Set(advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
        let hryServices: Set<CBUUID> = [HryFine.serviceUUID_FEE7, HryFine.serviceUUID_3802, HryFine.serviceUUID_FFE0]
        if !services.isDisjoint(with: hryServices) {
            pendingDeviceTypes[peripheral.identifier] = .hryfine
        }
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        activePeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        if !bondedDevices.contains(where: { $0.id == peripheral.identifier }) {
            let name = peripheral.name
                ?? "Device \(peripheral.identifier.uuidString.prefix(4).uppercased())"
            let type = pendingDeviceTypes.removeValue(forKey: peripheral.identifier)
                       ?? detectDeviceType(from: peripheral.name)
            bondedDevices.append(BondedDevice(id: peripheral.identifier, name: name, deviceType: type))
            saveBonded()
        }
        setConnectionState(peripheral.identifier, .connected)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        writeChars.removeValue(forKey: peripheral.identifier)
        if error != nil { scheduleReconnect(for: peripheral) }
        else             { setConnectionState(peripheral.identifier, .disconnected) }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        scheduleReconnect(for: peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        for char in service.characteristics ?? [] {

            // HryFine/L13 primary path: 3803 or FFE1 — subscribe + write ANCS activation packet.
            // The magic packet forces the peripheral to demand an encrypted link;
            // iOS intercepts the ATT_ERR_INSUFFICIENT_AUTHEN and shows the pairing dialog.
            if (char.uuid == HryFine.charUUID_3803 || char.uuid == HryFine.charUUID_FFE1)
                && writeChars[peripheral.identifier] == nil {
                writeChars[peripheral.identifier] = char
                peripheral.setNotifyValue(true, for: char)
                peripheral.writeValue(HryFine.ancsActivationPacket, for: char, type: .withResponse)
            }

            // HryFine/L13 fallback path: FEE7/36F6 — handshake + init sequence
            if char.uuid == HryFine.txCharUUID && writeChars[peripheral.identifier] == nil {
                writeChars[peripheral.identifier] = char
                sendL13Init(to: peripheral, char: char)
            }

            // FitPro / NUS — only if no HryFine char claimed writeChars first
            if NUS.txCharUUIDs.contains(char.uuid) && writeChars[peripheral.identifier] == nil {
                writeChars[peripheral.identifier] = char
                sendFitProInit(to: peripheral, char: char)
            }

            // Subscribe to all notify characteristics (36F5, ANCS Notification Source, etc.)
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }

            // Read readable characteristics for ANCS-capable devices.
            // Auth-gated reads surface ATT_ERR_INSUFFICIENT_AUTHEN → pairing dialog.
            let type = deviceType(for: peripheral.identifier)
            if type.requiresANCS {
                let knownSecure: Set<CBUUID> = [CBUUID(string: "2A19"), CBUUID(string: "2A24")]
                if char.properties.contains(.read) || knownSecure.contains(char.uuid) {
                    peripheral.readValue(for: char)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // After BLE bonding the device may expose additional services (e.g., ANCS relay).
        // Rediscover everything so new characteristics are handled.
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        // After the notify subscription on the activation char is confirmed, probe for
        // the ANCS relay service — it may only appear post-bonding.
        if characteristic.uuid == HryFine.charUUID_3803 || characteristic.uuid == HryFine.charUUID_FFE1 {
            peripheral.discoverServices([ANCSService.serviceUUID])
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        // The ANCS activation write succeeded: bonding is established.
        // Discover the ANCS relay service and send L13 configuration commands.
        if characteristic.uuid == HryFine.charUUID_3803 || characteristic.uuid == HryFine.charUUID_FFE1 {
            peripheral.discoverServices([ANCSService.serviceUUID])
            sendL13Config(to: peripheral, delay: 0.5)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, data.count >= 2 else { return }

        // MARK: L13 RX packet parsing (36F5 notify → iOS)
        // Header byte 0xAB identifies L13 protocol frames.
        // TODO: verify exact command bytes with nRF Connect scan of your specific firmware.
        if characteristic.uuid == HryFine.rxCharUUID {
            let header  = data[0]
            let cmdByte = data[1]
            switch (header, cmdByte) {

            case (0xAB, 0x03):
                // Heart rate — HR value at data[2] (0–255 bpm)
                guard data.count >= 3 else { break }
                heartRate = Int(data[2])

            case (0xAB, 0x06):
                // Step count — 4-byte big-endian at data[2...5]
                guard data.count >= 6 else { break }
                stepCount = Int(data[2]) << 24 | Int(data[3]) << 16
                           | Int(data[4]) << 8  | Int(data[5])

            case (0xAB, 0x04):
                // Battery level — single byte 0–100 at data[2]
                guard data.count >= 3 else { break }
                batteryLevel = Int(data[2])

            default:
                break
            }
        }
    }
}
