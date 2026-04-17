import Foundation
import CoreBluetooth
import Combine

// FitPro BLE protocol constants
private enum FitPro {
    // Common service/characteristic UUIDs used by FitPro-compatible bands
    static let serviceUUID        = CBUUID(string: "FFF0")
    static let writeCharUUID      = CBUUID(string: "FFF6")
    static let notifyCharUUID     = CBUUID(string: "FFF7")

    // Notification app category bytes
    enum Category: UInt8 {
        case generic   = 0x03
        case call      = 0x04
        case sms       = 0x09
        case whatsapp  = 0x0E
        case facebook  = 0x0F
        case twitter   = 0x10
        case instagram = 0x13
        case email     = 0x05
    }

    static func notificationPacket(category: UInt8, title: String, body: String) -> Data {
        // Packet format: AB 00 [len] 82 00 [category] 01 [title\0body\0]
        var payload: [UInt8] = [0x82, 0x00, category, 0x01]
        payload += Array((title + "\0").utf8)
        payload += Array((body + "\0").utf8)
        let header: [UInt8] = [0xAB, 0x00, UInt8(min(payload.count, 255))]
        return Data(header + payload)
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
        let category = categoryByte(for: appName)
        let packet = FitPro.notificationPacket(category: category, title: title, body: body)
        device.writeValue(packet, for: char, type: .withResponse)
    }

    private func categoryByte(for appName: String) -> UInt8 {
        let lower = appName.lowercased()
        if lower.contains("whatsapp") { return FitPro.Category.whatsapp.rawValue }
        if lower.contains("facebook") || lower.contains("messenger") { return FitPro.Category.facebook.rawValue }
        if lower.contains("twitter") || lower.contains("x.com") { return FitPro.Category.twitter.rawValue }
        if lower.contains("instagram") { return FitPro.Category.instagram.rawValue }
        if lower.contains("mail") { return FitPro.Category.email.rawValue }
        if lower.contains("message") || lower.contains("sms") { return FitPro.Category.sms.rawValue }
        return FitPro.Category.generic.rawValue
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
            peripheral.discoverCharacteristics([FitPro.writeCharUUID, FitPro.notifyCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == FitPro.writeCharUUID {
                writeCharacteristic = char
                flushPending()
            } else if char.uuid == FitPro.notifyCharUUID {
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
