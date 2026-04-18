import Foundation
import CoreBluetooth

// MARK: - Notification categories

enum NotifCategory: String, CaseIterable, Codable, Identifiable {
    case sms       = "Messages / SMS"
    case calls     = "Phone Calls"
    case wechat    = "WeChat"
    case qq        = "QQ"
    case facebook  = "Facebook / Messenger"
    case twitter   = "Twitter / X"
    case line      = "Line"
    case whatsapp  = "WhatsApp"
    case instagram = "Instagram"
    case email     = "Email"
    case generic   = "Other notifications"

    var id: String { rawValue }

    // Position in CMD_NOTIFICATIONS_ENABLE 11-byte payload
    var payloadIndex: Int {
        switch self {
        case .sms:       return 0
        case .calls:     return 1
        case .qq:        return 2
        case .wechat:    return 3
        case .facebook:  return 4
        case .twitter:   return 5
        case .line:      return 6
        case .whatsapp:  return 7
        case .instagram: return 8
        case .email:     return 9
        case .generic:   return 10
        }
    }
}

// MARK: - FitPro BLE protocol

private enum FitPro {
    static let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9d")
    static let txCharUUID  = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9d")
    static let rxCharUUID  = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9d")

    static let GROUP_GENERAL:      UInt8 = 0x12
    static let GROUP_REQUEST_DATA: UInt8 = 0x1A
    static let GROUP_BAND_INFO:    UInt8 = 0x20
    static let GROUP_BIND:         UInt8 = 0x14

    // CD [len_hi] [len_lo] [group] 01 [cmd] [payload_len_hi] [payload_len_lo] [payload...]
    static func packet(group: UInt8, cmd: UInt8, payload: [UInt8] = []) -> Data {
        let pLen = payload.count
        let fLen = 5 + pLen
        var bytes: [UInt8] = [
            0xCD,
            UInt8((fLen >> 8) & 0xFF), UInt8(fLen & 0xFF),
            group, 0x01, cmd,
            UInt8((pLen >> 8) & 0xFF), UInt8(pLen & 0xFF)
        ]
        bytes += payload
        return Data(bytes)
    }

    // CMD_NOTIFICATIONS_ENABLE — 11 bytes, one per category (0x01=on, 0x00=off)
    static func notificationsEnablePacket(enabled: [NotifCategory: Bool]) -> Data {
        var payload = [UInt8](repeating: 0x01, count: 11)
        for (cat, on) in enabled {
            payload[cat.payloadIndex] = on ? 0x01 : 0x00
        }
        return packet(group: GROUP_GENERAL, cmd: 0x07, payload: payload)
    }

    // CMD_UNBIND
    static var unbindPacket: Data { packet(group: GROUP_BIND, cmd: 0x00) }
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
    var connectionState: ConnectionState = .disconnected
    private enum CodingKeys: String, CodingKey { case id, name }
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

    private let storageKey       = "bondedDevices_v1"
    private let autoReconnectKey = "autoReconnect_v1"
    private let categoriesKey    = "notifCategories_v1"

    private let connectOptions: [String: Any] = [
        CBConnectPeripheralOptionRequiresANCS: true
    ]

    override init() {
        autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect_v1") as? Bool ?? true
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
        setConnectionState(peripheral.identifier, .connecting)
        central.connect(peripheral, options: connectOptions)
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

    // MARK: - Private — state helpers

    private func setConnectionState(_ id: UUID, _ state: ConnectionState) {
        guard let idx = bondedDevices.firstIndex(where: { $0.id == id }) else { return }
        bondedDevices[idx].connectionState = state
    }

    private func reconnectAll() {
        let uuids = bondedDevices.map { $0.id }
        guard !uuids.isEmpty else { return }
        for p in central.retrievePeripherals(withIdentifiers: uuids) { bond(to: p) }
    }

    private func scheduleReconnect(for peripheral: CBPeripheral) {
        guard autoReconnect,
              bondedDevices.contains(where: { $0.id == peripheral.identifier }) else { return }
        setConnectionState(peripheral.identifier, .reconnecting)
        central.connect(peripheral, options: connectOptions)
    }

    // MARK: - Private — FitPro init

    private func sendInitSequence(to peripheral: CBPeripheral, char: CBCharacteristic) {
        var t: TimeInterval = 0.05
        func send(_ data: Data, gap: TimeInterval = 0.2) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak peripheral] in
                guard let p = peripheral, p.state == .connected else { return }
                var offset = data.startIndex
                while offset < data.endIndex {
                    let end = data.index(offset, offsetBy: 20, limitedBy: data.endIndex) ?? data.endIndex
                    p.writeValue(data[offset..<end], for: char, type: .withoutResponse)
                    offset = end
                }
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
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0x15, payload: [0x00]))
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0xFF, payload: [0x01]))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x01))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x0F))
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x10))
        send(FitPro.packet(group: FitPro.GROUP_BAND_INFO, cmd: 0x02))

        // Enable notifications with current per-category settings
        send(FitPro.notificationsEnablePacket(enabled: notifCategories))
    }

    // Re-send CMD_NOTIFICATIONS_ENABLE to all currently connected devices
    private func resendNotifEnable() {
        for (id, char) in writeChars {
            guard let p = activePeripherals[id], p.state == .connected else { continue }
            let data = FitPro.notificationsEnablePacket(enabled: notifCategories)
            var offset = data.startIndex
            while offset < data.endIndex {
                let end = data.index(offset, offsetBy: 20, limitedBy: data.endIndex) ?? data.endIndex
                p.writeValue(data[offset..<end], for: char, type: .withoutResponse)
                offset = end
            }
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
            bondedDevices.append(BondedDevice(id: peripheral.identifier, name: name))
            saveBonded()
        }
        setConnectionState(peripheral.identifier, .connected)
        // Discover FitPro Nordic UART service to send init + notification-enable
        peripheral.discoverServices([FitPro.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        writeChars.removeValue(forKey: peripheral.identifier)
        if error != nil {
            scheduleReconnect(for: peripheral)
        } else {
            setConnectionState(peripheral.identifier, .disconnected)
        }
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
            if service.uuid == FitPro.serviceUUID {
                peripheral.discoverCharacteristics([FitPro.txCharUUID, FitPro.rxCharUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == FitPro.txCharUUID {
                writeChars[peripheral.identifier] = char
                sendInitSequence(to: peripheral, char: char)
            } else if char.uuid == FitPro.rxCharUUID {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }
}
