import Foundation
import CoreBluetooth
import Combine

// FitPro BLE protocol — Nordic UART service, Gadgetbridge-compatible packet format
private enum FitPro {
    // Nordic UART service UUIDs used by FitPro-compatible bands
    static let serviceUUID    = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9d")
    static let txCharUUID     = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9d") // write
    static let rxCharUUID     = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9d") // notify

    // Notification icon bytes (FitProConstants CMD_NOTIFICATION_* icons)
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
    // full_length = 5 + payload_len  (covers group, 01, cmd, payload_len_hi, payload_len_lo, payload)
    static func packet(group: UInt8, cmd: UInt8, payload: [UInt8]) -> Data {
        let payloadLen = payload.count
        let fullLen = 5 + payloadLen
        var bytes: [UInt8] = [
            0xCD,
            UInt8((fullLen >> 8) & 0xFF),
            UInt8(fullLen & 0xFF),
            group,
            0x01,
            cmd,
            UInt8((payloadLen >> 8) & 0xFF),
            UInt8(payloadLen & 0xFF)
        ]
        bytes += payload
        return Data(bytes)
    }

    // CMD_NOTIFICATION_MESSAGE: group=0x12, cmd=0x12
    // Payload: [icon] [sender\0] [subject\0] [body\0]
    static func notificationPacket(icon: UInt8, sender: String, subject: String, body: String) -> Data {
        var payload: [UInt8] = [icon]
        payload += Array((sender + "\0").utf8)
        payload += Array((subject + "\0").utf8)
        payload += Array((body + "\0").utf8)
        return packet(group: 0x12, cmd: 0x12, payload: payload)
    }

    // CMD_NOTIFICATIONS_ENABLE: group=0x01, cmd=0x07 — sent once on connect
    static var enableNotificationsPacket: Data {
        let payload: [UInt8] = [0x1, 0x1, 0x1, 0x1, 0x1, 0x1, 0x1, 0x1, 0x1, 0x1, 0x1]
        return packet(group: 0x01, cmd: 0x07, payload: payload)
    }
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
    private var writeCharacteristic: CBCharacteristic?
    private let savedDeviceKey = "savedBandIdentifier"
    private var pendingNotifications: [(appName: String, title: String, body: String)] = []

    private let mtu = 20 // BLE default ATT MTU payload

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices = []
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [FitPro.serviceUUID], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
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

    func sendNotification(appName: String, title: String, body: String) {
        guard let char = writeCharacteristic, let device = connectedDevice,
              device.state == .connected else {
            pendingNotifications.append((appName, title, body))
            return
        }
        let icon = iconByte(for: appName)
        let packet = FitPro.notificationPacket(icon: icon, sender: appName, subject: title, body: body)
        writeChunked(packet, to: device, characteristic: char)
    }

    // Splits data into 20-byte ATT MTU chunks and writes sequentially
    private func writeChunked(_ data: Data, to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = data.index(offset, offsetBy: mtu, limitedBy: data.endIndex) ?? data.endIndex
            let chunk = data[offset..<end]
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            offset = end
        }
    }

    private func iconByte(for appName: String) -> UInt8 {
        let lower = appName.lowercased()
        if lower.contains("whatsapp")                         { return FitPro.Icon.whatsapp.rawValue }
        if lower.contains("facebook") || lower.contains("messenger") { return FitPro.Icon.facebook.rawValue }
        if lower.contains("twitter") || lower.contains("x.com")      { return FitPro.Icon.twitter.rawValue }
        if lower.contains("instagram")                        { return FitPro.Icon.instagram.rawValue }
        if lower.contains("line")                             { return FitPro.Icon.line.rawValue }
        if lower.contains("wechat")                           { return FitPro.Icon.wechat.rawValue }
        if lower.contains("message") || lower.contains("sms") { return FitPro.Icon.sms.rawValue }
        return FitPro.Icon.generic.rawValue
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            attemptReconnect()
        }
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
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedDevice?.identifier == peripheral.identifier {
            connectedDevice = nil
            writeCharacteristic = nil
            connectionState = .idle
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .error
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
                writeCharacteristic = char
                // Enable notifications on the band after discovering write characteristic
                writeChunked(FitPro.enableNotificationsPacket, to: peripheral, characteristic: char)
                flushPending()
            } else if char.uuid == FitPro.rxCharUUID {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    private func flushPending() {
        let queue = pendingNotifications
        pendingNotifications = []
        for item in queue {
            sendNotification(appName: item.appName, title: item.title, body: item.body)
        }
    }

    private func attemptReconnect() {
        guard let savedId = UserDefaults.standard.string(forKey: savedDeviceKey),
              let uuid = UUID(uuidString: savedId) else { return }
        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = known.first {
            connect(to: peripheral)
        }
    }
}
