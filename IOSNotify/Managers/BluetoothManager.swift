import Foundation
import CoreBluetooth

enum ConnectionState: String, Codable {
    case disconnected  = "Disconnected"
    case connecting    = "Connecting…"
    case connected     = "Connected"
    case reconnecting  = "Reconnecting…"
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
    @Published var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: autoReconnectKey) }
    }

    private var central: CBCentralManager!
    private var activePeripherals: [UUID: CBPeripheral] = [:]
    private let storageKey       = "bondedDevices_v1"
    private let autoReconnectKey = "autoReconnect_v1"

    // Connect options shared by bonding, reconnect, and state restoration
    private let connectOptions: [String: Any] = [
        CBConnectPeripheralOptionRequiresANCS: true
    ]

    override init() {
        autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect_v1") as? Bool ?? true
        super.init()
        loadBonded()
        // RestoreIdentifierKey enables iOS to relaunch the app after termination
        // and call willRestoreState so pending connections resume automatically.
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
        central.connect(peripheral, options: connectOptions)
    }

    func disconnect(id: UUID) {
        guard let p = activePeripherals[id] else { return }
        // cancelPeripheralConnection also cancels any pending connect() call,
        // so autoReconnect will not fire for a user-initiated disconnect.
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

    private func scheduleReconnect(for peripheral: CBPeripheral) {
        guard autoReconnect,
              bondedDevices.contains(where: { $0.id == peripheral.identifier }) else { return }
        setConnectionState(peripheral.identifier, .reconnecting)
        // CoreBluetooth's connect() is persistent — it retries in the background
        // indefinitely until the peripheral is found, without draining the battery
        // (the Bluetooth hardware handles the scan).
        central.connect(peripheral, options: connectOptions)
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

    // Called when iOS restores the central manager after the app was terminated.
    // Reclaim any peripherals that were being managed before termination.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in peripherals {
                activePeripherals[p.identifier] = p
                p.delegate = self
            }
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
        if !bondedDevices.contains(where: { $0.id == peripheral.identifier }) {
            let name = peripheral.name ?? "Device \(peripheral.identifier.uuidString.prefix(4).uppercased())"
            bondedDevices.append(BondedDevice(id: peripheral.identifier, name: name))
            saveBonded()
        }
        setConnectionState(peripheral.identifier, .connected)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // error == nil means user-initiated (cancelPeripheralConnection); skip reconnect.
        if error != nil {
            scheduleReconnect(for: peripheral)
        } else {
            setConnectionState(peripheral.identifier, .disconnected)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Treat a failed connect attempt the same as an unexpected disconnect.
        scheduleReconnect(for: peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {}
