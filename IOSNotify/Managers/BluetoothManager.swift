import Foundation
import CoreBluetooth
import Combine

// FitPro BLE protocol — Nordic UART service, Gadgetbridge-compatible
private enum FitPro {
    static let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9d")
    static let txCharUUID  = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9d") // write
    static let rxCharUUID  = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9d") // notify

    // Command groups
    static let GROUP_GENERAL:      UInt8 = 0x12
    static let GROUP_REQUEST_DATA: UInt8 = 0x1A
    static let GROUP_BAND_INFO:    UInt8 = 0x20
    static let GROUP_BIND:         UInt8 = 0x14
    static let GROUP_RESET:        UInt8 = 0x1D

    // Notification icon bytes
    enum Icon: UInt8 {
        case sms       = 0x01
        case wechat    = 0x03
        case facebook  = 0x04
        case twitter   = 0x05
        case line      = 0x07
        case whatsapp  = 0x08
        case instagram = 0x10
        case generic   = 0x00
    }

    // Packet: CD [full_len_hi] [full_len_lo] [group] 01 [cmd] [payload_len_hi] [payload_len_lo] [payload]
    // full_len = 5 + payload_len
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

    // CMD_NOTIFICATION_MESSAGE: group=0x12, cmd=0x12
    static func notificationPacket(icon: UInt8, sender: String, subject: String, body: String) -> Data {
        var payload: [UInt8] = [icon]
        payload += Array((sender  + "\0").utf8)
        payload += Array((subject + "\0").utf8)
        payload += Array((body    + "\0").utf8)
        return packet(group: GROUP_GENERAL, cmd: 0x12, payload: payload)
    }

    // CMD_NOTIFICATIONS_ENABLE — group MUST be 0x12, not 0x01
    static var enableNotificationsPacket: Data {
        let payload: [UInt8] = [0x1,0x1,0x1,0x1,0x1,0x1,0x1,0x1,0x1,0x1,0x1]
        return packet(group: GROUP_GENERAL, cmd: 0x07, payload: payload)
    }

    // CMD_UNBIND — sent to factory-reset the bond (group=0x14, cmd=0x00)
    static var unbindPacket: Data { packet(group: GROUP_BIND, cmd: 0x00) }
}

enum BandConnectionState: String {
    case idle       = "Not connected"
    case scanning   = "Scanning..."
    case connecting = "Connecting..."
    case connected  = "Connected"
    case error      = "Error"
}

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BluetoothManager()

    @Published var connectionState: BandConnectionState = .idle
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?

    private var centralManager: CBCentralManager!
    private var writeChar: CBCharacteristic?
    private let savedDeviceKey = "savedBandIdentifier"
    private var pendingNotifications: [(appName: String, title: String, body: String)] = []
    private let mtu = 20

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices = []
        connectionState = .scanning
        // Scan without service-UUID filter — many FitPro bands don't advertise
        // the Nordic UART UUID in their advertisement packet
        centralManager.scanForPeripherals(withServices: nil,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        if connectionState == .scanning { connectionState = .idle }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        connectionState = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let device = connectedDevice else { return }
        centralManager.cancelPeripheralConnection(device)
    }

    /// Factory-reset the BLE bond. Call this if the band refuses to connect.
    func unbind() {
        guard let char = writeChar, let device = connectedDevice else { return }
        Task { @MainActor in DiagnosticLog.shared.log("Sending UNBIND to band", tag: "BT") }
        writeChunked(FitPro.unbindPacket, to: device, characteristic: char)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.disconnect()
        }
    }

    func sendNotification(appName: String, title: String, body: String) {
        guard let char = writeChar, let device = connectedDevice,
              device.state == .connected else {
            pendingNotifications.append((appName, title, body))
            return
        }
        let icon = iconByte(for: appName)
        writeChunked(FitPro.notificationPacket(icon: icon, sender: appName, subject: title, body: body),
                     to: device, characteristic: char)
    }

    // MARK: - Private helpers

    private func writeChunked(_ data: Data, to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = data.index(offset, offsetBy: mtu, limitedBy: data.endIndex) ?? data.endIndex
            peripheral.writeValue(data[offset..<end], for: characteristic, type: .withoutResponse)
            offset = end
        }
    }

    /// Gadgetbridge initialization sequence with required 200 ms inter-command delays.
    private func sendInitSequence(to peripheral: CBPeripheral, char: CBCharacteristic) {
        Task { @MainActor in DiagnosticLog.shared.log("Sending FitPro init sequence", tag: "BT") }

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

        // 1. INIT1
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0x0A, payload: [0x02]))

        // 2. Set time (4-byte big-endian Unix timestamp)
        let ts = UInt32(Date().timeIntervalSince1970)
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0x01, payload: [
            UInt8((ts >> 24) & 0xFF), UInt8((ts >> 16) & 0xFF),
            UInt8((ts >>  8) & 0xFF), UInt8( ts        & 0xFF)
        ]))

        // 3. Request INIT1 data
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x0A))

        // 4. Request INIT2 data
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x0C))

        // 5. Set language (0x00 = English)
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0x15, payload: [0x00]))

        // 6. INIT3
        send(FitPro.packet(group: FitPro.GROUP_GENERAL, cmd: 0xFF, payload: [0x01]))

        // 7. Request data 0x01
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x01))

        // 8. Request 0x0F
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x0F))

        // 9. Request HW info
        send(FitPro.packet(group: FitPro.GROUP_REQUEST_DATA, cmd: 0x10))

        // 10. Band info
        send(FitPro.packet(group: FitPro.GROUP_BAND_INFO, cmd: 0x02))

        // 11. Enable notifications
        send(FitPro.enableNotificationsPacket)

        // 12. Flush any queued notifications
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.3) { [weak self] in
            self?.flushPending()
        }
    }

    private func flushPending() {
        let queue = pendingNotifications
        pendingNotifications = []
        for item in queue { sendNotification(appName: item.appName, title: item.title, body: item.body) }
    }

    private func attemptReconnect() {
        guard let savedId = UserDefaults.standard.string(forKey: savedDeviceKey),
              let uuid = UUID(uuidString: savedId) else { return }
        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = known.first { connect(to: peripheral) }
    }

    private func iconByte(for appName: String) -> UInt8 {
        let l = appName.lowercased()
        if l.contains("whatsapp")                           { return FitPro.Icon.whatsapp.rawValue }
        if l.contains("facebook") || l.contains("messenger") { return FitPro.Icon.facebook.rawValue }
        if l.contains("twitter")  || l.contains("x.com")   { return FitPro.Icon.twitter.rawValue  }
        if l.contains("instagram")                          { return FitPro.Icon.instagram.rawValue }
        if l.contains("line")                               { return FitPro.Icon.line.rawValue     }
        if l.contains("wechat")                             { return FitPro.Icon.wechat.rawValue   }
        if l.contains("message")  || l.contains("sms")     { return FitPro.Icon.sms.rawValue      }
        return FitPro.Icon.generic.rawValue
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { attemptReconnect() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevice = peripheral
        connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([FitPro.serviceUUID])
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedDeviceKey)
        Task { @MainActor in DiagnosticLog.shared.log("Connected to \(peripheral.name ?? peripheral.identifier.uuidString)", tag: "BT") }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedDevice?.identifier == peripheral.identifier {
            connectedDevice = nil
            writeChar = nil
            connectionState = .idle
            Task { @MainActor in DiagnosticLog.shared.log("Disconnected from band", tag: "BT") }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .error
        Task { @MainActor in DiagnosticLog.shared.log("Failed to connect: \(error?.localizedDescription ?? "unknown")", tag: "ERROR") }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == FitPro.serviceUUID {
            peripheral.discoverCharacteristics([FitPro.txCharUUID, FitPro.rxCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == FitPro.txCharUUID {
                writeChar = char
                sendInitSequence(to: peripheral, char: char)
            } else if char.uuid == FitPro.rxCharUUID {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }
}
