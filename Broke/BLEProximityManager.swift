import Combine
import CoreBluetooth
import Foundation
import UIKit

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
    nonisolated(unsafe) private static let heartbeatUUID =
        CBUUID(string: "6F2A0006-8F4D-4B1A-9F1C-7D19D2A10001")
    private static let restorationIdentifier =
        "dev.kunjadia.broke.central"
    private static let lockThresholdRSSI = -50
    private static let unlockThresholdRSSI = -55
    private static let calibrationSampleTarget = 20

    @Published private(set) var status: Status = .starting
    @Published private(set) var pods: [PodSnapshot] = []
    @Published private(set) var isNear = false
    @Published private(set) var calibrationSession: CalibrationSession?
    @Published private(set) var calibrationResult: CalibrationResult?

    private let defaults = UserDefaults.standard
    private var central: CBCentralManager!
    private var runtimes: [UUID: PodRuntime] = [:]
    private var pairedPods: [String: StoredPod] = [:]
    private var rssiTimer: Timer?

    /// Background wake support. When iOS wakes us for a BLE event we get a few
    /// seconds of execution, and the foreground RSSI timer is suspended — so
    /// near/far would never settle. `didConnect` starts a short burst of
    /// readRSSI() calls instead, held open by a background task assertion.
    /// Without this, walking back into the room reconnected the pod but never
    /// produced the one sample `isNear` needs, so re-locking waited for the
    /// app to be opened — the lock only worked with the app on screen.
    private var backgroundReadsRemaining = 0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var calibrationSamples: [Double] = []
    private var calibrationHeldIsNear: Bool?

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
        let boundaryRSSI: Double?
        let hysteresisBuffer: Double?

        var id: String { podID }
        var displayName: String { room?.isEmpty == false ? room! : podID }
    }

    struct CalibrationSession {
        let podID: String
        let room: String
        let targetSampleCount: Int
        var sampleCount: Int
        var currentRSSI: Double?
    }

    struct CalibrationResult {
        let podID: String
        let succeeded: Bool
        let message: String
        let averageRSSI: Double?
        let bufferRSSI: Double?
    }

    private struct StoredPod: Codable {
        let podID: String
        var peripheralID: UUID
        var room: String
        var boundaryRSSI: Double?
        var hysteresisBuffer: Double?
    }

    private final class PodRuntime {
        let peripheral: CBPeripheral
        var podID: String?
        var isConnected = false
        var calibrationRSSI = -59
        var thresholdRSSI = BLEProximityManager.lockThresholdRSSI
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
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier
            ]
        )
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
            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
            boundaryRSSI: nil,
            hysteresisBuffer: nil
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

    func startCalibration(for podID: String) {
        guard let stored = pairedPods[podID] else { return }

        calibrationSamples = []
        calibrationResult = nil
        calibrationHeldIsNear = isNear
        calibrationSession = CalibrationSession(
            podID: podID,
            room: stored.room,
            targetSampleCount: Self.calibrationSampleTarget,
            sampleCount: 0,
            currentRSSI: nil
        )

        for runtime in runtimes.values {
            runtime.nearSamples = 0
            runtime.farSamples = 0
        }
        publishSnapshots()
    }

    func cancelCalibration() {
        calibrationSamples = []
        calibrationSession = nil
        calibrationHeldIsNear = nil
        publishSnapshots()
    }

    func clearCalibrationResult() {
        calibrationResult = nil
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        reconnectKnownPods()
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

    private func reconnectKnownPods() {
        let identifiers = pairedPods.values.map(\.peripheralID)
        guard !identifiers.isEmpty else { return }

        central.registerForConnectionEvents(
            options: [
                .peripheralUUIDs: identifiers
            ]
        )

        for peripheral in central.retrievePeripherals(withIdentifiers: identifiers) {
            connectIfNeeded(peripheral)
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

        if peripheral.state == .connected {
            runtime.isConnected = true
            peripheral.discoverServices([Self.serviceUUID])
            publishSnapshots()
            // A pod restored in the connected state never passes through
            // didConnect, so without this the background sampler never runs
            // after a relaunch and near/far sits unset until the next
            // heartbeat arrives.
            beginBackgroundSampling(peripheral)
        } else if !runtime.isConnected, peripheral.state == .disconnected {
            central.connect(
                peripheral,
                options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnNotificationKey: true,
                    CBConnectPeripheralOptionEnableAutoReconnect: true
                ]
            )
        }
    }

    private func processRSSI(_ value: Int, for peripheralID: UUID) {
        guard value < 0, value > -120, let runtime = runtimes[peripheralID] else { return }

        let filtered = runtime.smoothedRSSI.map {
            ($0 * 0.35) + (Double(value) * 0.65)
        } ?? Double(value)
        runtime.smoothedRSSI = filtered
        runtime.estimatedDistance = pow(
            10,
            (Double(runtime.calibrationRSSI) - filtered) / 22
        )

        guard let podID = runtime.podID else {
            publishSnapshots()
            return
        }

        if let calibrationSession {
            if calibrationSession.podID == podID {
                calibrationSamples.append(Double(value))
                self.calibrationSession?.sampleCount = calibrationSamples.count
                self.calibrationSession?.currentRSSI = Double(value)
                if calibrationSamples.count >= Self.calibrationSampleTarget {
                    finishCalibration()
                } else {
                    publishSnapshots()
                }
            }
            return
        }

        guard pairedPods[podID] != nil else {
            publishSnapshots()
            return
        }

        let threshold = thresholds(for: podID)
        if !runtime.isNear {
            runtime.nearSamples = filtered >= threshold.lock
                ? runtime.nearSamples + 1
                : 0
            if runtime.nearSamples >= 1 {
                runtime.isNear = true
                runtime.nearSamples = 0
                runtime.farSamples = 0
                BackgroundJournal.record("pod near (\(Int(filtered)) dBm)")
            }
        } else {
            runtime.farSamples = filtered <= threshold.unlock
                ? runtime.farSamples + 1
                : 0
            if runtime.farSamples >= 1 {
                runtime.isNear = false
                runtime.nearSamples = 0
                runtime.farSamples = 0
                BackgroundJournal.record("pod far (\(Int(filtered)) dBm)")
            }
        }

        publishSnapshots()
    }

    private func publishSnapshots() {
        pods = runtimes.values.compactMap { runtime in
            guard let podID = runtime.podID else { return nil }
            let stored = pairedPods[podID]
            let threshold = thresholds(for: podID)
            return PodSnapshot(
                podID: podID,
                peripheralID: runtime.peripheral.identifier,
                room: stored?.room,
                isPaired: stored != nil,
                isConnected: runtime.isConnected,
                smoothedRSSI: runtime.smoothedRSSI,
                estimatedDistance: runtime.estimatedDistance,
                thresholdRSSI: Int(threshold.lock.rounded()),
                isNear: stored != nil && runtime.isNear,
                boundaryRSSI: stored?.boundaryRSSI,
                hysteresisBuffer: stored?.hysteresisBuffer
            )
        }
        .sorted {
            if $0.isPaired != $1.isPaired { return $0.isPaired }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        if let heldIsNear = calibrationHeldIsNear {
            isNear = heldIsNear
        } else {
            isNear = pods.contains(where: { $0.isPaired && $0.isNear })
        }
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
                room: "My Pod",
                boundaryRSSI: nil,
                hysteresisBuffer: nil
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

    private func thresholds(for podID: String) -> (lock: Double, unlock: Double) {
        guard
            let stored = pairedPods[podID],
            let boundary = stored.boundaryRSSI,
            let buffer = stored.hysteresisBuffer
        else {
            return (Double(Self.lockThresholdRSSI), Double(Self.unlockThresholdRSSI))
        }

        return (boundary + buffer, boundary - buffer)
    }

    private func finishCalibration() {
        guard let session = calibrationSession else { return }
        calibrationSession = nil

        let average = calibrationSamples.reduce(0, +) / Double(calibrationSamples.count)
        let variance = calibrationSamples.reduce(0) { partialResult, sample in
            partialResult + pow(sample - average, 2)
        } / Double(calibrationSamples.count)
        let standardDeviation = sqrt(variance)
        let buffer = min(max(standardDeviation * 1.5, 3.0), 8.0)

        if var stored = pairedPods[session.podID] {
            stored.boundaryRSSI = average
            stored.hysteresisBuffer = buffer
            pairedPods[session.podID] = stored
            savePairedPods()
        }

        calibrationResult = CalibrationResult(
            podID: session.podID,
            succeeded: true,
            message: "Boundary saved. Broke locks above \(Int((average + buffer).rounded())) dBm and unlocks below \(Int((average - buffer).rounded())) dBm.",
            averageRSSI: average,
            bufferRSSI: buffer
        )
        calibrationSamples = []
        calibrationHeldIsNear = nil
        for runtime in runtimes.values {
            runtime.nearSamples = 0
            runtime.farSamples = 0
        }
        publishSnapshots()
    }
}

extension BLEProximityManager: CBCentralManagerDelegate {
    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        Task { @MainActor in
            BackgroundJournal.record("relaunched by Bluetooth, \(restored.count) pod(s) restored")
            for peripheral in restored {
                self.connectIfNeeded(peripheral)
            }
        }
    }

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
            BackgroundJournal.record("pod connected")
            peripheral.discoverServices([Self.serviceUUID])
            self.publishSnapshots()
            self.beginBackgroundSampling(peripheral)
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
            BackgroundJournal.record("pod disconnected")
            self.publishSnapshots()
            self.startScanning()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        Task { @MainActor in
            if let runtime = self.runtimes[peripheral.identifier] {
                runtime.isConnected = false
                runtime.isNear = false
                runtime.nearSamples = 0
                runtime.farSamples = 0
            }
            BackgroundJournal.record("pod disconnected (reconnecting: \(isReconnecting))")
            self.publishSnapshots()

            if !isReconnecting {
                self.connectIfNeeded(peripheral)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        connectionEventDidOccur event: CBConnectionEvent,
        for peripheral: CBPeripheral
    ) {
        Task { @MainActor in
            self.connectIfNeeded(peripheral)
        }
    }
}

extension BLEProximityManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID })
        else { return }

        peripheral.discoverCharacteristics(
            [
                Self.calibrationUUID,
                Self.thresholdUUID,
                Self.podIDUUID,
                Self.heartbeatUUID
            ],
            for: service
        )
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        service.characteristics?.forEach { characteristic in
            peripheral.readValue(for: characteristic)
            if characteristic.uuid == Self.heartbeatUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
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
                runtime.thresholdRSSI = Self.lockThresholdRSSI
            case Self.heartbeatUUID:
                peripheral.readRSSI()
            default:
                break
            }
            self.publishSnapshots()
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.heartbeatUUID else { return }
        if error != nil || !characteristic.isNotifying {
            peripheral.setNotifyValue(true, for: characteristic)
        } else {
            peripheral.readRSSI()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            self.processRSSI(RSSI.intValue, for: peripheral.identifier)
            self.continueBackgroundSampling(peripheral)
        }
    }
}

// MARK: - Background sampling

extension BLEProximityManager {
    /// Starts the burst of RSSI reads that stands in for the foreground timer
    /// during a background wake. No-op while the app is active.
    fileprivate func beginBackgroundSampling(_ peripheral: CBPeripheral) {
        guard UIApplication.shared.applicationState != .active else { return }
        holdBackgroundWindow()
        backgroundReadsRemaining = 5
        peripheral.readRSSI()
    }

    fileprivate func continueBackgroundSampling(_ peripheral: CBPeripheral) {
        guard backgroundReadsRemaining > 0 else { return }
        backgroundReadsRemaining -= 1
        guard backgroundReadsRemaining > 0 else {
            releaseBackgroundWindow()
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.backgroundReadsRemaining > 0 else { return }
            peripheral.readRSSI()
        }
    }

    /// Asks iOS to keep us running while the burst completes; released when
    /// the reads finish, when the system says time is up, or by the failsafe.
    private func holdBackgroundWindow() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BrokePodEvent") { [weak self] in
            Task { @MainActor in self?.releaseBackgroundWindow() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.releaseBackgroundWindow()
        }
    }

    private func releaseBackgroundWindow() {
        backgroundReadsRemaining = 0
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
