import Combine
import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class FocusLockModel: ObservableObject {
    static let isNFCTestBypassEnabled = false
    private static let lockFeedbackDelay: UInt64 = 300_000_000
    private static let duplicateScanWindow: TimeInterval = 1.25

    @Published var selection: FamilyActivitySelection {
        didSet {
            updateActiveProfileSelection()
            if isLocked {
                applyShields()
            }
        }
    }
    @Published private(set) var blockProfiles: [BlockProfile]
    @Published private(set) var activeProfileID: UUID
    @Published private(set) var isLocked: Bool
    @Published private(set) var displayedIsLocked: Bool
    @Published private(set) var hasPairedTag: Bool
    @Published private(set) var emergencyUnlocksRemaining: Int
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published private(set) var lockDurationText = "00:00"
    @Published var lockBanner: LockBanner?
    @Published var popup: FocusPopup?

    private let store = ManagedSettingsStore(named: .init("BrokeFocus"))
    private let nfc = NFCService()
    private let defaults = UserDefaults.standard
    private var isNFCLocked: Bool
    private var isBLEPodNear = false
    private var pendingLockFeedback: (from: Bool, to: Bool)?
    private var lockFeedbackTask: Task<Void, Never>?
    private var lockBannerTask: Task<Void, Never>?
    private var lockStartedAt: Date?
    private var lockTimer: AnyCancellable?
    private var lastAcceptedPayload: String?
    private var lastAcceptedPayloadDate: Date?
    private var cancellables = Set<AnyCancellable>()

    private enum Key {
        static let selection = "focusSelection"
        static let blockProfiles = "blockProfiles"
        static let activeProfileID = "activeBlockProfileID"
        static let isLocked = "focusIsLocked"
        static let tagID = "focusTagID"
        static let emergencyUnlocksRemaining = "emergencyUnlocksRemaining"
        static let lockStartedAt = "lockStartedAt"
    }

    init() {
        let savedProfiles: [BlockProfile]
        if let data = defaults.data(forKey: Key.blockProfiles),
           let decoded = try? JSONDecoder().decode([BlockProfile].self, from: data),
           !decoded.isEmpty {
            savedProfiles = decoded
        } else {
            let legacySelection: FamilyActivitySelection
            if let data = defaults.data(forKey: Key.selection),
               let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
                legacySelection = saved
            } else {
                legacySelection = FamilyActivitySelection()
            }
            savedProfiles = [
                BlockProfile(name: "Focus", selection: legacySelection)
            ]
        }

        let savedActiveID = defaults.string(forKey: Key.activeProfileID).flatMap(UUID.init(uuidString:))
        let initialProfile = savedProfiles.first(where: { $0.id == savedActiveID })
            ?? savedProfiles[0]
        blockProfiles = savedProfiles
        activeProfileID = initialProfile.id
        selection = initialProfile.selection
        isNFCLocked = defaults.bool(forKey: Key.isLocked)
        isLocked = isNFCLocked
        displayedIsLocked = isNFCLocked
        lockStartedAt = defaults.object(forKey: Key.lockStartedAt) as? Date
        hasPairedTag = defaults.string(forKey: Key.tagID)?.hasPrefix("broke://tag/v1/") == true
        if defaults.object(forKey: Key.emergencyUnlocksRemaining) == nil {
            let initialEmergencyUnlocks = 3
            emergencyUnlocksRemaining = initialEmergencyUnlocks
            defaults.set(initialEmergencyUnlocks, forKey: Key.emergencyUnlocksRemaining)
        } else {
            emergencyUnlocksRemaining = defaults.integer(forKey: Key.emergencyUnlocksRemaining)
        }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus

        if isLocked && hasScreenTimeAuthorization {
            applyShields()
            ensureLockTimerRunning()
        } else {
            clearLockTimer()
        }

        requestNotificationAuthorization()

        AuthorizationCenter.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.authorizationStatus = status
                self.reconcileLockState(showPopup: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.playPendingLockFeedback()
            }
            .store(in: &cancellables)

        nfc.onRead = { [weak self] payload in
            Task { @MainActor in
                self?.handleScannedPayload(payload)
            }
        }
        nfc.onPair = { [weak self] payload in
            Task { @MainActor in
                self?.defaults.set(payload, forKey: Key.tagID)
                self?.hasPairedTag = true
                self?.popup = .tagReady
            }
        }
        nfc.onError = { [weak self] message in
            Task { @MainActor in
                self?.popup = .error(message)
            }
        }
    }

    var selectedItemCount: Int {
        Self.itemCount(in: selection)
    }

    var hasSelection: Bool {
        selectedItemCount > 0
    }

    var hasScreenTimeAuthorization: Bool {
        authorizationStatus == .approved || authorizationStatus == .approvedWithDataAccess
    }

    var authorizationMessage: String {
        switch authorizationStatus {
        case .approved, .approvedWithDataAccess:
            "Screen Time access enabled"
        case .denied:
            "Screen Time access denied"
        case .notDetermined:
            "Screen Time access required"
        @unknown default:
            "Screen Time authorization unavailable"
        }
    }

    var canScan: Bool {
        if Self.isNFCTestBypassEnabled {
            return hasSelection
        }
        return hasSelection && hasPairedTag && NFCService.isAvailable
    }

    var canUseEmergencyUnlock: Bool {
        isLocked && emergencyUnlocksRemaining > 0
    }

    var footerMessage: String {
        if Self.isNFCTestBypassEnabled {
            return "Test mode: NFC is disabled. Use the button to lock and unlock."
        }
        if !NFCService.isAvailable {
            return "NFC scanning requires a supported physical iPhone."
        }
        if !hasSelection {
            return "Choose at least one app before pairing your tag."
        }
        if !hasPairedTag {
            return "Pair the unique prewritten tag supplied with Broke."
        }
        return "Only your paired Broke tag can change this lock."
    }

    func requestAuthorizationIfNeeded() async {
#if targetEnvironment(simulator)
        return
#else
        let currentStatus = AuthorizationCenter.shared.authorizationStatus
        authorizationStatus = currentStatus
        guard currentStatus != .approved, currentStatus != .approvedWithDataAccess else {
            reconcileLockState(showPopup: false)
            return
        }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            reconcileLockState(showPopup: false)

            if !hasScreenTimeAuthorization {
                popup = .error(
                    "Screen Time access was not approved. Open Settings > Screen Time and allow Broke before testing the block."
                )
            }
        } catch {
            popup = .error("Screen Time access is required to block your selected apps.")
        }
#endif
    }

    func requestAuthorization() {
        Task {
            await requestAuthorizationIfNeeded()
        }
    }

    func pairTag() {
        guard hasSelection else {
            popup = .error("Choose the apps you want to block first.")
            return
        }

        nfc.pair()
    }

    func addBlockProfile(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = BlockProfile(
            name: trimmedName.isEmpty ? "List \(blockProfiles.count + 1)" : trimmedName,
            selection: FamilyActivitySelection()
        )
        blockProfiles.append(profile)
        selectBlockProfile(profile.id)
    }

    func selectBlockProfile(_ id: UUID) {
        guard id != activeProfileID,
              let profile = blockProfiles.first(where: { $0.id == id }) else {
            return
        }

        activeProfileID = id
        selection = profile.selection
        saveProfiles()
    }

    func deleteBlockProfile(_ id: UUID) {
        guard blockProfiles.count > 1,
              let index = blockProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasActive = activeProfileID == id
        blockProfiles.remove(at: index)
        if wasActive {
            let replacement = blockProfiles[min(index, blockProfiles.count - 1)]
            activeProfileID = replacement.id
            selection = replacement.selection
        }
        saveProfiles()
    }

    func scanTag() {
        if Self.isNFCTestBypassEnabled {
            if isNFCLocked {
                unlockFromNFC()
            } else {
                lockFromNFC()
            }
            return
        }

        guard hasPairedTag else {
            popup = .error("Pair your prewritten Broke tag before starting a focus session.")
            return
        }
        nfc.scan(successMessage: isNFCLocked ? "Broke is unlocking your apps." : "Broke is locking your apps.")
    }

    func useEmergencyUnlock() {
        guard isLocked else { return }
        guard emergencyUnlocksRemaining > 0 else {
            popup = .emergencyUnavailable
            return
        }

        emergencyUnlocksRemaining -= 1
        defaults.set(emergencyUnlocksRemaining, forKey: Key.emergencyUnlocksRemaining)

        isNFCLocked = false
        defaults.set(false, forKey: Key.isLocked)
        reconcileLockState(showPopup: false)
        popup = .emergencyUnlocked(emergencyUnlocksRemaining)
    }

    func handleIncomingTagURL(_ url: URL) {
        guard let payload = NFCService.validatedPayload(url.absoluteString) else {
            return
        }
        handleScannedPayload(payload)
    }

    func updateBLEProximity(isNear: Bool) {
        guard isNear != isBLEPodNear else { return }
        isBLEPodNear = isNear
        reconcileLockState(showPopup: isNear)
    }

    private func handleScannedPayload(_ payload: String) {
        guard payload == defaults.string(forKey: Key.tagID) else {
            popup = .wrongTag
            return
        }

        let now = Date()
        if payload == lastAcceptedPayload,
           let lastAcceptedPayloadDate,
           now.timeIntervalSince(lastAcceptedPayloadDate) < Self.duplicateScanWindow {
            return
        }
        lastAcceptedPayload = payload
        lastAcceptedPayloadDate = now

        if isNFCLocked {
            unlockFromNFC()
        } else {
            lockFromNFC()
        }
    }

    private func lockFromNFC() {
        guard hasSelection else {
            popup = .error("Your block list is empty. Choose at least one app.")
            return
        }

        isNFCLocked = true
        defaults.set(true, forKey: Key.isLocked)
        reconcileLockState(showPopup: true)
    }

    private func unlockFromNFC() {
        isNFCLocked = false
        defaults.set(false, forKey: Key.isLocked)
        if isBLEPodNear {
            reconcileLockState(showPopup: false)
            popup = .podStillNear
        } else {
            reconcileLockState(showPopup: true)
        }
    }

    private func reconcileLockState(showPopup: Bool) {
        let hasActiveTrigger = isNFCLocked || isBLEPodNear
        let shouldLock = hasSelection && hasActiveTrigger && hasScreenTimeAuthorization

        if shouldLock {
            applyShields()
        } else {
            store.clearAllSettings()
        }

        if hasActiveTrigger && hasSelection && !hasScreenTimeAuthorization {
            isLocked = false
            updateDisplayedLockStateImmediately(false)
            if showPopup {
                popup = .screenTimeRequired
            }
            return
        }

        guard shouldLock != isLocked else { return }
        let previousLockState = isLocked
        isLocked = shouldLock
        updateLockTimer(for: shouldLock)
        showLockBanner(isLocked: shouldLock)
        sendLockNotification(isLocked: shouldLock)
        scheduleLockFeedback(from: previousLockState, to: shouldLock)
    }

    private func applyShields() {
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
    }

    private func scheduleLockFeedback(from oldLockState: Bool, to newLockState: Bool) {
        lockFeedbackTask?.cancel()

        guard UIApplication.shared.applicationState == .active else {
            pendingLockFeedback = (oldLockState, newLockState)
            return
        }

        lockFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.lockFeedbackDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.34)) {
                displayedIsLocked = newLockState
            }
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(newLockState ? .warning : .success)
        }
    }

    private func playPendingLockFeedback() {
        guard let lockFeedback = pendingLockFeedback else { return }
        pendingLockFeedback = nil
        scheduleLockFeedback(from: lockFeedback.from, to: lockFeedback.to)
    }

    private func updateLockTimer(for isLocked: Bool) {
        if isLocked {
            if lockStartedAt == nil {
                let start = Date()
                lockStartedAt = start
                defaults.set(start, forKey: Key.lockStartedAt)
            }
            ensureLockTimerRunning()
        } else {
            clearLockTimer()
        }
    }

    private func ensureLockTimerRunning() {
        updateLockDurationText()
        guard lockTimer == nil else { return }

        lockTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateLockDurationText()
            }
    }

    private func clearLockTimer() {
        lockTimer?.cancel()
        lockTimer = nil
        lockStartedAt = nil
        defaults.removeObject(forKey: Key.lockStartedAt)
        lockDurationText = "00:00"
    }

    private func updateLockDurationText() {
        guard let lockStartedAt else {
            lockDurationText = "00:00"
            return
        }

        let elapsed = max(0, Int(Date().timeIntervalSince(lockStartedAt)))
        let hours = elapsed / 3_600
        let minutes = (elapsed % 3_600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            lockDurationText = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            lockDurationText = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func showLockBanner(isLocked: Bool) {
        lockBannerTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            lockBanner = LockBanner(isLocked: isLocked)
        }

        lockBannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                lockBanner = nil
            }
        }
    }

    private func requestNotificationAuthorization() {
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                // Notification permission is optional; the in-app banner still works.
            }
        }
    }

    private func sendLockNotification(isLocked: Bool) {
        let content = UNMutableNotificationContent()
        content.title = isLocked ? "Broke locked" : "Broke unlocked"
        content.body = isLocked
            ? "Your selected apps are blocked."
            : "Your selected apps are available again."
        content.sound = .default
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "broke-lock-state-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func updateDisplayedLockStateImmediately(_ isLocked: Bool) {
        lockFeedbackTask?.cancel()
        pendingLockFeedback = nil
        displayedIsLocked = isLocked
    }

    private func updateActiveProfileSelection() {
        guard let index = blockProfiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }
        blockProfiles[index].selection = selection
        saveProfiles()
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(blockProfiles) else { return }
        defaults.set(data, forKey: Key.blockProfiles)
        defaults.set(activeProfileID.uuidString, forKey: Key.activeProfileID)
        defaults.removeObject(forKey: Key.selection)
    }

    static func itemCount(in selection: FamilyActivitySelection) -> Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }
}

struct BlockProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var selection: FamilyActivitySelection

    init(id: UUID = UUID(), name: String, selection: FamilyActivitySelection) {
        self.id = id
        self.name = name
        self.selection = selection
    }

    var itemCount: Int {
        FocusLockModel.itemCount(in: selection)
    }
}

struct LockBanner: Identifiable, Equatable {
    let id = UUID()
    let isLocked: Bool

    var title: String {
        isLocked ? "Broke locked" : "Broke unlocked"
    }

    var message: String {
        isLocked ? "Your selected apps are blocked." : "Your selected apps are available again."
    }

    var symbol: String {
        isLocked ? "lock.fill" : "lock.open.fill"
    }

    var tint: Color {
        isLocked
            ? Color(red: 0.91, green: 0.25, blue: 0.13)
            : Color(red: 0.075, green: 0.078, blue: 0.07)
    }
}

enum FocusPopup: Identifiable {
    case tagReady
    case wrongTag
    case podStillNear
    case screenTimeRequired
    case emergencyUnlocked(Int)
    case emergencyUnavailable
    case error(String)

    var id: String {
        switch self {
        case .tagReady: "tagReady"
        case .wrongTag: "wrongTag"
        case .podStillNear: "podStillNear"
        case .screenTimeRequired: "screenTimeRequired"
        case .emergencyUnlocked(let remaining): "emergencyUnlocked-\(remaining)"
        case .emergencyUnavailable: "emergencyUnavailable"
        case .error(let message): "error-\(message)"
        }
    }

    var title: String {
        switch self {
        case .tagReady: "Tag is ready."
        case .wrongTag: "Not your key."
        case .podStillNear: "A pod is still nearby."
        case .screenTimeRequired: "Permission needed."
        case .emergencyUnlocked: "Emergency unlock used."
        case .emergencyUnavailable: "No emergency unlocks left."
        case .error: "Something went wrong."
        }
    }

    var message: String {
        switch self {
        case .tagReady:
            "This prewritten Broke tag is now paired with this phone. Scan it whenever you want to lock or unlock."
        case .wrongTag:
            "This NFC tag does not match the one paired with Broke. Find your original focus tag and try again."
        case .podStillNear:
            "The NFC lock is off, but your apps will stay blocked until you leave the range of every paired pod."
        case .screenTimeRequired:
            "The pod is in range, but iOS has not allowed Broke to manage Screen Time yet. Enable access and try again."
        case .emergencyUnlocked(let remaining):
            "\(remaining) emergency unlock\(remaining == 1 ? "" : "s") remaining. These only reset if Broke is deleted and reinstalled."
        case .emergencyUnavailable:
            "All 3 emergency unlocks have been used. Scan your paired tag to unlock Broke."
        case .error(let message):
            message
        }
    }

    var symbol: String {
        switch self {
        case .tagReady: "checkmark.seal.fill"
        case .wrongTag: "key.slash.fill"
        case .podStillNear: "dot.radiowaves.left.and.right"
        case .screenTimeRequired: "hourglass.badge.exclamationmark"
        case .emergencyUnlocked: "lock.open.fill"
        case .emergencyUnavailable: "lock.slash.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .tagReady, .emergencyUnlocked:
            Color(red: 0.08, green: 0.46, blue: 0.3)
        case .wrongTag, .podStillNear, .screenTimeRequired, .emergencyUnavailable, .error:
            Color(red: 0.83, green: 0.24, blue: 0.17)
        }
    }

    var buttonTitle: String {
        switch self {
        case .tagReady: "GOT IT"
        case .podStillNear: "GOT IT"
        case .screenTimeRequired: "ENABLE ACCESS"
        case .emergencyUnlocked: "OK"
        case .wrongTag, .emergencyUnavailable, .error: "TRY AGAIN"
        }
    }
}
