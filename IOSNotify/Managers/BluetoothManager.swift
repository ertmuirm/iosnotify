import Foundation
import CoreBluetooth

enum ConnectionState: String, Codable {
    case disconnected = "Disconnected"
    case connecting   = "Connecting…"
    case connected    = "Connected"
}

struct BondedDevice: Identifiable, Codable {
    let id: UUID      // matches CBPeripheral.identifier
    let name: String  // captured at bond time

    var connectionState: ConnectionState = .disconnected

    private enum CodingKeys: String, CodingKey { case id, name }
}

class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published var bondedDevices: [BondedDevice] = []
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown

    private var central: CBCentralManager!
    private var activePeripherals: [UUID: CBPeripheral] = [:]
    private let storageKey = "bondedDevices_v1"

    override init() {
        super.init()
        loadBonded()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        discoveredDevices = []
        isScanning = true
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func bond(to peripheral: CBPeripheral) {
        stopScan()
        setConnectionState(peripheral.identifier, .connecting)
        central.connect(peripheral, options: [CBConnectPeripheralOptionRequiresANCS: true])
    }

    func disconnect(id: UUID) {
        guard let p = activePeripherals[id] else { return }
        central.cancelPeripheralConnection(p)
    }

    func removeDevice(id: UUID) {
        disconnect(id: id)
        bondedDevices.removeAll { $0.id == id }
        activePeripherals.removeValue(forKey: id)
        saveBonded()
    }

    // MARK: - Private

    private func setConnectionState(_ id: UUID, _ state: ConnectionState) {
        guard let idx = bondedDevices.firstIndex(where: { $0.id == id }) else { return }
        bondedDevices[idx].connectionState = state
    }

    private func reconnectAll() {
        let uuids = bondedDevices.map { $0.id }
        guard !uuids.isEmpty else { return }
        let known = central.retrievePeripherals(withIdentifiers: uuids)
        for p in known { bond(to: p) }
    }

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
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn { reconnectAll() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        activePeripherals[peripheral.identifier] = peripheral
        if !bondedDevices.contains(where: { $0.id == peripheral.identifier }) {
            let name = peripheral.name ?? "Device \(peripheral.identifier.uuidString.prefix(4).uppercased())"
            bondedDevices.append(BondedDevice(id: peripheral.identifier, name: name))
            saveBonded()
        }
        setConnectionState(peripheral.identifier, .connected)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        setConnectionState(peripheral.identifier, .disconnected)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        setConnectionState(peripheral.identifier, .disconnected)
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {}
