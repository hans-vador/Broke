import Combine
import CoreBluetooth
import Foundation

@MainActor
final class BLEProximityManager: NSObject, ObservableObject {
    nonisolated(unsafe) static let serviceUUID =
        CBUUID(string: "6F2A0001-8F4D-4B1A-9F1C-7D19D2A10001")

    nonisolated(unsafe) private static let calibrationUUID =
        CBUUID(string: "6F2A0002-8F4D-4B1A-9F1C-7D19D2A10001")
    nonisolated(unsafe) private static let thresholdUUID =
        CBUUID(string: "6F2A0003-8F4D-4B1A-9F1C-7D19D2A10001")
    nonisolated(unsafe) private static let podIDUUID =
        CBUUID(string: "6F2A0005-8F4D-4B1A-9F1C-7D19D2A10001")

    @Published private(set) var status: Status = .starting
    @Published private(set) var pods: [PodSnapshot] = []
    @Published private(set) var isNear = false

    private let defaults = UserDefaults.standard
    private var central: CBCentralManager!
    private var runtimes: [UUID: PodRuntime] = [:]
    private var pairedPods: [String: StoredPod] = [:]
    private var rssiTimer: Timer?

    private enum Key {
        static let pairedPods = "blePairedPods"
        static let legacyPodID = "blePairedPodID"
        static let legacyPeripheralID = "blePairedPeripheralID"
    }

    enum Status: Equatable {
        case starting
        case unavailable
        case scanning
        case ready

        var label: String {
            switch self {
            case .starting: "Starting Bluetooth"
            case .unavailable: "Bluetooth unavailable"
            case .scanning: "Looking for pods"
            case .ready: "Monitoring pods"
            }
        }
    }

    struct PodSnapshot: Identifiable {
        let podID: String
        let peripheralID: UUID
        let room: String?
        let isPaired: Bool
        let isConnected: Bool
        let smoothedRSSI: Double?
        let estimatedDistance: Double?
        let thresholdRSSI: Int
        let isNear: Bool

        var id: String { podID }
        var displayName: String { room?.isEmpty == false ? room! : podID }
    }

    private struct StoredPod: Codable {
        let podID: String
        var peripheralID: UUID
        var room: String
    }

    private final class PodRuntime {
        let peripheral: CBPeripheral
        var podID: String?
        var isConnected = false
        var calibrationRSSI = -59
        var thresholdRSSI = -70
        var smoothedRSSI: Double?
        var estimatedDistance: Double?
        var isNear = false
        var nearSamples = 0
        var farSamples = 0

        init(peripheral: CBPeripheral) {
            self.peripheral = peripheral
        }
    }

    override init() {
        super.init()
        loadPairedPods()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var pairedPodCount: Int {
        pairedPods.count
    }

    var discoveredUnpairedPods: [PodSnapshot] {
        pods.filter { !$0.isPaired }
    }

    var pairedPodSnapshots: [PodSnapshot] {
        pods.filter(\.isPaired)
    }

    func pairPod(_ podID: String, room: String) {
        guard let runtime = runtimes.values.first(where: { $0.podID == podID }) else { return }
        pairedPods[podID] = StoredPod(
            podID: podID,
            peripheralID: runtime.peripheral.identifier,
            room: room.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        savePairedPods()
        publishSnapshots()
    }

    func forgetPod(_ podID: String) {
        pairedPods.removeValue(forKey: podID)
        savePairedPods()
        if let runtime = runtimes.values.first(where: { $0.podID == podID }) {
            runtime.isNear = false
            runtime.nearSamples = 0
            runtime.farSamples = 0
        }
        publishSnapshots()
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        status = runtimes.values.contains(where: \.isConnected) ? .ready : .scanning
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        if rssiTimer == nil {
            rssiTimer = Timer.scheduledTimer(
                timeInterval: 1,
                target: self,
                selector: #selector(pollConnectedPods),
                userInfo: nil,
                repeats: true
            )
        }
    }

    @objc private func pollConnectedPods() {
        for runtime in runtimes.values where runtime.isConnected {
            runtime.peripheral.readRSSI()
        }
    }

    private func connectIfNeeded(_ peripheral: CBPeripheral) {
        let runtime = runtimes[peripheral.identifier] ?? PodRuntime(peripheral: peripheral)
        runtimes[peripheral.identifier] = runtime
        peripheral.delegate = self

        guard !runtime.isConnected, peripheral.state == .disconnected else { return }
        central.connect(peripheral)
    }

    private func processRSSI(_ value: Int, for peripheralID: UUID) {
        guard value < 0, value > -120, let runtime = runtimes[peripheralID] else { return }

        let filtered = runtime.smoothedRSSI.map {
            ($0 * 0.8) + (Double(value) * 0.2)
        } ?? Double(value)
        runtime.smoothedRSSI = filtered
        runtime.estimatedDistance = pow(
            10,
            (Double(runtime.calibrationRSSI) - filtered) / 22
        )

        guard let podID = runtime.podID, pairedPods[podID] != nil else {
            publishSnapshots()
            return
        }

        if !runtime.isNear {
            runtime.nearSamples = filtered >= Double(runtime.thresholdRSSI)
                ? runtime.nearSamples + 1
                : 0
            if runtime.nearSamples >= 3 {
                runtime.isNear = true
                runtime.nearSamples = 0
                runtime.farSamples = 0
            }
        } else {
            runtime.farSamples = filtered <= Double(runtime.thresholdRSSI - 5)
                ? runtime.farSamples + 1
                : 0
            if runtime.farSamples >= 5 {
                runtime.isNear = false
                runtime.nearSamples = 0
                runtime.farSamples = 0
            }
        }

        publishSnapshots()
    }

    private func publishSnapshots() {
        pods = runtimes.values.compactMap { runtime in
            guard let podID = runtime.podID else { return nil }
            let stored = pairedPods[podID]
            return PodSnapshot(
                podID: podID,
                peripheralID: runtime.peripheral.identifier,
                room: stored?.room,
                isPaired: stored != nil,
                isConnected: runtime.isConnected,
                smoothedRSSI: runtime.smoothedRSSI,
                estimatedDistance: runtime.estimatedDistance,
                thresholdRSSI: runtime.thresholdRSSI,
                isNear: stored != nil && runtime.isNear
            )
        }
        .sorted {
            if $0.isPaired != $1.isPaired { return $0.isPaired }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        isNear = pods.contains(where: { $0.isPaired && $0.isNear })
        status = runtimes.values.contains(where: \.isConnected) ? .ready : .scanning
    }

    private func loadPairedPods() {
        if let data = defaults.data(forKey: Key.pairedPods),
           let stored = try? JSONDecoder().decode([StoredPod].self, from: data) {
            pairedPods = Dictionary(uniqueKeysWithValues: stored.map { ($0.podID, $0) })
            return
        }

        if let podID = defaults.string(forKey: Key.legacyPodID),
           let peripheralString = defaults.string(forKey: Key.legacyPeripheralID),
           let peripheralID = UUID(uuidString: peripheralString) {
            pairedPods[podID] = StoredPod(
                podID: podID,
                peripheralID: peripheralID,
                room: "My Pod"
            )
            savePairedPods()
        }
    }

    private func savePairedPods() {
        guard let data = try? JSONEncoder().encode(Array(pairedPods.values)) else { return }
        defaults.set(data, forKey: Key.pairedPods)
        defaults.removeObject(forKey: Key.legacyPodID)
        defaults.removeObject(forKey: Key.legacyPeripheralID)
    }

    private func readInt(from data: Data) -> Int? {
        guard data.count >= MemoryLayout<Int32>.size else { return nil }
        return data.withUnsafeBytes {
            Int(Int32(littleEndian: $0.loadUnaligned(as: Int32.self)))
        }
    }
}

extension BLEProximityManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                self.startScanning()
            } else {
                self.status = .unavailable
                self.isNear = false
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            self.connectIfNeeded(peripheral)
            self.processRSSI(RSSI.intValue, for: peripheral.identifier)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let runtime = self.runtimes[peripheral.identifier] else { return }
            runtime.isConnected = true
            peripheral.discoverServices([Self.serviceUUID])
            self.publishSnapshots()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.runtimes[peripheral.identifier]?.isConnected = false
            self.publishSnapshots()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            if let runtime = self.runtimes[peripheral.identifier] {
                runtime.isConnected = false
                runtime.isNear = false
                runtime.nearSamples = 0
                runtime.farSamples = 0
            }
            self.publishSnapshots()
            self.startScanning()
        }
    }
}

extension BLEProximityManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID })
        else { return }

        peripheral.discoverCharacteristics(
            [Self.calibrationUUID, Self.thresholdUUID, Self.podIDUUID],
            for: service
        )
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        service.characteristics?.forEach(peripheral.readValue)
        peripheral.readRSSI()
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        Task { @MainActor in
            guard let runtime = self.runtimes[peripheral.identifier] else { return }
            switch characteristic.uuid {
            case Self.podIDUUID:
                guard let podID = String(data: data, encoding: .utf8) else { return }
                runtime.podID = podID
                if var stored = self.pairedPods[podID],
                   stored.peripheralID != peripheral.identifier {
                    stored.peripheralID = peripheral.identifier
                    self.pairedPods[podID] = stored
                    self.savePairedPods()
                }
            case Self.calibrationUUID:
                if let value = self.readInt(from: data) {
                    runtime.calibrationRSSI = value
                }
            case Self.thresholdUUID:
                if let value = self.readInt(from: data) {
                    runtime.thresholdRSSI = value
                }
            default:
                break
            }
            self.publishSnapshots()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            self.processRSSI(RSSI.intValue, for: peripheral.identifier)
        }
    }
}
