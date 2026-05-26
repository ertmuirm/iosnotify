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

    // FitPro protocol: index into the 11-byte enable array
    var payloadIndex: Int {
        switch self {
        case .sms:      return 0
        case .calls:    return 1
        case .qq:       return 2
        case .wechat:   return 3
        case .facebook: return 4
        case .twitter:  return 5
        case .line:     return 6
        case .whatsapp: return 7
        case .outlook:  return 8
        case .email:    return 9
        case .generic:  return 10
        }
    }

    // L13 protocol: bit position in the 32-bit App Push Toggle bitmask
    var l13Bit: UInt32 {
        switch self {
        case .calls:    return 0x00000001
        case .sms:      return 0x00000002
        case .wechat:   return 0x00000004
        case .qq:       return 0x00000008
        case .facebook: return 0x00000010
        case .twitter:  return 0x00000020
        case .whatsapp: return 0x00000040
        case .outlook:  return 0x00000080  // occupies Instagram's original bit
        case .email:    return 0x00000100
        case .line:     return 0x00000200
        case .generic:  return 0x00000400
        }
    }
}

// MARK: - Nordic UART Service UUIDs (two common variants)

private enum NUS {
    // FitPro clone variant (last byte d)
    static let txChar_v1 = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9d")
    // Standard NUS / L13 variant (last byte e)
    static let txChar_v2 = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    // Notify characteristics
    static let rxChar_v1 = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9d")
    static let rxChar_v2 = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")

    static let txCharUUIDs: Set<CBUUID> = [txChar_v1, txChar_v2]
    static let rxCharUUIDs: Set<CBUUID> = [rxChar_v1, rxChar_v2]
}

// MARK: - FitPro BLE protocol (CD-header, Nordic UART)

private enum FitPro {
    static let GROUP_GENERAL:      UInt8 = 0x12
    static let GROUP_REQUEST_DATA: UInt8 = 0x1A
    static let GROUP_BAND_INFO:    UInt8 = 0x20
    static let GROUP_BIND:         UInt8 = 0x14

    // CD [len_hi] [len_lo] [group] 01 [cmd] [plen_hi] [plen_lo] [payload...]
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

// MARK: - L13 BLE protocol (AB-header, Nordic UART)
//
// Frame: AB 00 [LEN] [CAT] [CMD] [PAYLOAD...]
// LEN = bytes from CAT to end of frame.
// Packets with 4+ payload bytes append XOR(CAT, CMD, payload...) as checksum,
// which accounts for the +1 in the documented length values.

private enum L13 {
    static func packet(cat: UInt8, cmd: UInt8, payload: [UInt8] = []) -> Data {
        let dataBytes: [UInt8] = [cat, cmd] + payload
        let needsChecksum = payload.count >= 4
        let len = UInt8(dataBytes.count + (needsChecksum ? 1 : 0))
        var result: [UInt8] = [0xAB, 0x00, len] + dataBytes
        if needsChecksum { result.append(dataBytes.reduce(0, ^)) }
        return Data(result)
        // notifications: AB 00 07 02 01 [m3 m2 m1 m0] [XOR]  ✓
        // time sync:     AB 00 0A 01 01 Y1 Y2 MM DD HH MI SS [XOR]  ✓
        // vibration:     AB 00 04 04 02 [int] [rep]  ✓
        // find device:   AB 00 03 03 01 [01/00]  ✓
    }

    // App Push Toggle — 32-bit bitmask of enabled notification categories
    static func notificationsPacket(enabled: [NotifCategory: Bool]) -> Data {
        var mask: UInt32 = 0
        for (cat, on) in enabled where on { mask |= cat.l13Bit }
        return packet(cat: 0x02, cmd: 0x01, payload: [
            UInt8((mask >> 24) & 0xFF), UInt8((mask >> 16) & 0xFF),
            UInt8((mask >>  8) & 0xFF), UInt8( mask        & 0xFF)
        ])
    }

    // Vibration: intensity 00=off…03=high, repeats = pulse count
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

    // Find Device — triggers vibrate/beep loop on the watch
    static func findBandPacket(start: Bool) -> Data {
        packet(cat: 0x03, cmd: 0x01, payload: [start ? 0x01 : 0x00])
    }

    // Bind — application-layer handshake that tells the watch an iOS device is
    // trying to pair. The firmware responds by issuing a BLE Security Request,
    // which causes iOS to show the native pairing dialog and create the system
    // bond (ⓘ icon + "Share System Notifications" toggle).
    // Must be sent before any other command. AB 00 03 01 02 01
    static var bindPacket: Data { packet(cat: 0x01, cmd: 0x02, payload: [0x01]) }

    // Time Sync — must be sent on every connection or the watch shows wrong time
    static func timeSyncPacket() -> Data {
        let c = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: Date())
        let y = c.year ?? 2026
        return packet(cat: 0x01, cmd: 0x01, payload: [
            UInt8((y >> 8) & 0xFF), UInt8(y & 0xFF),
            UInt8(c.month  ?? 1),
            UInt8(c.day    ?? 1),
            UInt8(c.hour   ?? 0),
            UInt8(c.minute ?? 0),
            UInt8(c.second ?? 0)
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

    private var central: CBCentralManager!
    private var activePeripherals: [UUID: CBPeripheral] = [:]
    private var writeChars: [UUID: CBCharacteristic] = [:]
    private var pendingDeviceTypes: [UUID: DeviceType] = [:]

    private let storageKey       = "bondedDevices_v1"
    private let autoReconnectKey = "autoReconnect_v1"
    private let categoriesKey    = "notifCategories_v1"

    private func connectOptions(for type: DeviceType) -> [String: Any] {
        switch type {
        case .hryfine, .genericAncs:
            // RequiresANCS does two things:
            // 1. Tells iOS this connection is for ANCS (enables "Share System Notifications" toggle)
            // 2. If the peripheral has any encrypted GATT characteristic, iOS shows the
            //    "Bluetooth Pairing Request" dialog when we subscribe/read/write it
            //    (ATT_ERR_INSUFFICIENT_AUTHEN → iOS initiates SMP bonding)
            return [CBConnectPeripheralOptionRequiresANCS: true]
        case .fitpro:
            return [:]
        }
    }

    private func detectDeviceType(from name: String?) -> DeviceType {
        let n = name?.lowercased() ?? ""
        if n.contains("hryfine") || n.contains("hryf") || n == "l13" { return .hryfine }
        if n.contains("fitpro") || n.contains("fit pro") { return .fitpro }
        return .genericAncs
    }

    override init() {
        autoReconnect   = UserDefaults.standard.object(forKey: "autoReconnect_v1") as? Bool ?? true
        notifCategories = Self.loadCategories()
        super.init()
        loadBonded()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "io.iosnotify.central"]
        )
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        discoveredDevices = []
        isScanning = true
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
        let type = detectDeviceType(from: peripheral.name)
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
        case .hryfine: (start, stop) = (L13.findBandPacket(start: true),  L13.findBandPacket(start: false))
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
        central.connect(peripheral,
                        options: connectOptions(for: deviceType(for: peripheral.identifier)))
    }

    // Write to a peripheral; uses .withResponse when the characteristic supports it
    // so authentication-gated writes trigger the iOS pairing dialog.
    // Chunks automatically for payloads > 20 bytes (FitPro only in practice).
    private func write(_ data: Data, to peripheral: CBPeripheral,
                       characteristic: CBCharacteristic) {
        if data.count > 20 {
            var offset = data.startIndex
            while offset < data.endIndex {
                let end = data.index(offset, offsetBy: 20, limitedBy: data.endIndex) ?? data.endIndex
                peripheral.writeValue(data[offset..<end], for: characteristic,
                                      type: .withoutResponse)
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
        // Method B: bind packet sent immediately with .withResponse (ATT Write Request).
        // Using .withResponse is critical — it either:
        //   (a) succeeds and the firmware issues a BLE Security Request → iOS pairing dialog, OR
        //   (b) fails with CBATTError.insufficientAuthentication, which CoreBluetooth intercepts
        //       and automatically converts into the iOS pairing dialog.
        // The .withoutResponse path (ATT Write Command) does not trigger either mechanism.
        peripheral.writeValue(L13.bindPacket, for: char, type: .withResponse)

        // Delay subsequent commands to allow the pairing handshake to complete (~2 s).
        var t: TimeInterval = 2.5
        func send(_ data: Data, gap: TimeInterval = 0.2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self, weak peripheral] in
                guard let self, let p = peripheral, p.state == .connected else { return }
                self.write(data, to: p, characteristic: char)
            }
            t += gap
        }
        send(L13.timeSyncPacket())
        let vib = bondedDevices.first(where: { $0.id == peripheral.identifier })?.vibrationLevel ?? 3
        send(L13.vibrationPacket(level: vib))
        send(L13.notificationsPacket(enabled: notifCategories))
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
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        activePeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        if !bondedDevices.contains(where: { $0.id == peripheral.identifier }) {
            let name = peripheral.name ?? "Device \(peripheral.identifier.uuidString.prefix(4).uppercased())"
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
        else            { setConnectionState(peripheral.identifier, .disconnected) }
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
        let type = deviceType(for: peripheral.identifier)
        for char in service.characteristics ?? [] {
            // NUS write characteristic — matches both UUID variants (9d and 9e)
            if NUS.txCharUUIDs.contains(char.uuid) {
                writeChars[peripheral.identifier] = char
                sendInitSequence(to: peripheral, char: char)
            }
            // Subscribe to all notify characteristics
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
            // Method A: read Model Number (2A24) and Battery Level (2A19) unconditionally
            // on ANCS devices. If authentication-gated, CoreBluetooth receives
            // CBATTError.insufficientAuthentication in didUpdateValueFor and iOS shows
            // the pairing dialog. All other readable characteristics are also attempted.
            if type.requiresANCS {
                let knownSecure: Set<CBUUID> = [CBUUID(string: "2A19"), CBUUID(string: "2A24")]
                if char.properties.contains(.read) || knownSecure.contains(char.uuid) {
                    peripheral.readValue(for: char)
                }
            }
        }
    }

    // CoreBluetooth calls this after every .withResponse write.
    // If the L13 bind characteristic requires authentication, the error is
    // CBATTError.insufficientAuthentication and iOS automatically shows the
    // pairing dialog — we do not need to handle it ourselves.
    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {}

    // Same mechanism for reads: if any characteristic returns insufficientAuthentication,
    // iOS intercepts the error and initiates the pairing handshake automatically.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {}
}
