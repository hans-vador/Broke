import Combine
import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class FocusLockModel: ObservableObject {
#if DEV_BUILD
    /// Dev-only: lets the primary button drive the real lock/unlock path without
    /// a physical tag. Backed by UserDefaults so the dev panel can flip it on
    /// device; it is a compile-time `false` in shipped builds, so a forgotten
    /// toggle can never reach TestFlight or the App Store.
    private static let nfcBypassKey = "devNFCTestBypass"
    static var isNFCTestBypassEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: nfcBypassKey) }
        set { UserDefaults.standard.set(newValue, forKey: nfcBypassKey) }
    }
#else
    static let isNFCTestBypassEnabled = false
#endif
    private static let lockFeedbackDelay: UInt64 = 300_000_000
    private static let duplicateScanWindow: TimeInterval = 1.25
#if DEBUG
    private static let isMascotDemoEnabled = ProcessInfo.processInfo.environment["MASCOT_DEMO"] == "1"
    /// QA hook: pretend a block list exists so the simulator (which has no
    /// real FamilyActivityPicker) can still exercise the lock controls.
    ///
    /// The simulator can never grant Family Controls authorization, so the
    /// onboarding permission gate is a dead end there — the dev build stands in
    /// for it automatically. `FAKE_SELECTION=0` restores the real gate; on a
    /// device the hook stays off unless `FAKE_SELECTION=1` asks for it.
    private static let usesFakeSelection: Bool = {
        if let flag = ProcessInfo.processInfo.environment["FAKE_SELECTION"] {
            return flag == "1"
        }
#if DEV_BUILD && targetEnvironment(simulator)
        return true
#else
        return false
#endif
    }()
#endif

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
    /// How this phone locks. Chosen once during onboarding, then permanent.
    @Published private(set) var lockMode: LockMode
    /// Seconds left on an app-only unlock request, or nil when none is running.
    @Published private(set) var unlockCountdown: Int?
    /// Whether a paired pod currently has us in range. Published because in
    /// combined mode the pod can take or release the lock without the lock
    /// state itself changing, and the copy on screen needs to keep up.
    @Published private(set) var isBLEPodNear = false

    private let store = ManagedSettingsStore(named: .init("BrokeFocus"))
    private let nfc = NFCService()
    private let defaults = UserDefaults.standard
    private var isManualLocked: Bool
    private var pendingLockFeedback: (from: Bool, to: Bool)?
    private var lockFeedbackTask: Task<Void, Never>?
    private var lockBannerTask: Task<Void, Never>?
    private var lockStartedAt: Date?
    private var lockTimer: AnyCancellable?
    private var lastAcceptedPayload: String?
    private var lastAcceptedPayloadDate: Date?
    private var unlockCountdownTask: Task<Void, Never>?
    private var hasRequestedNotifications = false
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
        lockMode = LockModeStore.current ?? .timer
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
        let savedLockState = defaults.bool(forKey: Key.isLocked)
#if DEBUG
        // Demo mode always starts at idle and does not inherit a persisted lock.
        isManualLocked = Self.isMascotDemoEnabled ? false : savedLockState
#else
        isManualLocked = savedLockState
#endif
        isLocked = isManualLocked
        displayedIsLocked = isManualLocked
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
#if DEBUG
        if Self.usesFakeSelection { return true }
#endif
        return selectedItemCount > 0
    }

    var hasScreenTimeAuthorization: Bool {
#if DEBUG
        // The simulator can never grant Screen Time, so the QA hook stands in
        // for it. Shield application is already no-op'd on the simulator.
        if Self.usesFakeSelection { return true }
#endif
        return authorizationStatus == .approved || authorizationStatus == .approvedWithDataAccess
    }

    var authorizationMessage: String {
        // Read through the same accessor the rest of the UI uses, so the
        // simulator's stand-in for Screen Time doesn't leave the banner saying
        // "required" next to a green tick and a calm colour.
        if hasScreenTimeAuthorization { return "Screen Time access enabled" }
        return switch authorizationStatus {
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

    /// Whether the home screen's primary lock control should be tappable.
    var canToggleLock: Bool {
        guard hasSelection else { return false }
        switch lockMode {
        case .timer:
            return true
        case .tag, .both:
            // In combined mode the tag is still the thing you tap; the pod just
            // locks you as well.
            if Self.isNFCTestBypassEnabled { return true }
            return hasPairedTag && NFCService.isAvailable
        case .pod:
            // In pod mode the room does the locking; there is nothing to tap.
            return false
        }
    }

    /// Title for the primary control, which differs a lot per mode.
    var primaryActionTitle: String {
        switch lockMode {
        case .tag:
            return displayedIsLocked ? "Scan to unlock" : "Scan to lock"
        case .pod:
            return displayedIsLocked ? "Blocked by your pod" : "Waiting for your pod"
        case .both:
            // The tag stays the control you tap. If the pod is also holding the
            // lock, scanning explains that rather than pretending to fail.
            return displayedIsLocked ? "Scan to unlock" : "Scan to lock"
        case .timer:
            if unlockCountdown != nil { return "Hang tight…" }
            return displayedIsLocked ? "Let me back in" : "Lock it up"
        }
    }

    var primaryActionSymbol: String {
        switch lockMode {
        case .tag: "wave.3.right"
        case .pod: "sensor.tag.radiowaves.forward"
        case .both: "wave.3.right"
        case .timer: displayedIsLocked ? "hourglass" : "lock.fill"
        }
    }

    var canUseEmergencyUnlock: Bool {
        isLocked && emergencyUnlocksRemaining > 0
    }

    var footerMessage: String {
        if !hasSelection {
            return "Pick at least one app, or there's nothing to save you from."
        }
        switch lockMode {
        case .tag, .both:
            if Self.isNFCTestBypassEnabled {
                return "Test mode: NFC is off. Use the button to lock and unlock."
            }
            if !NFCService.isAvailable {
                return "NFC needs a real iPhone. The simulator can't tap a tag."
            }
            if !hasPairedTag {
                return "Pair the tag that came in the box to get started."
            }
            if lockMode == .both && isBLEPodNear {
                return "Your pod has you right now. The tag can't override it."
            }
            return lockMode.homeHint
        case .pod:
            return LockMode.pod.homeHint
        case .timer:
            return LockMode.timer.homeHint
        }
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

    /// Called once onboarding commits the permanent mode, so the live model
    /// starts routing through the right trigger immediately.
    func adoptCommittedLockMode() {
        guard let committed = LockModeStore.current, committed != lockMode else { return }
        lockMode = committed
        reconcileLockState(showPopup: false)
    }

    /// The one thing the home screen's primary button calls. Each mode routes
    /// it somewhere different.
    func primaryAction() {
        switch lockMode {
        case .tag, .both:
            scanTag()
        case .pod:
            break   // proximity drives everything; the control is display-only
        case .timer:
            if unlockCountdown != nil {
                cancelUnlockCountdown(userInitiated: true)
            } else if isManualLocked {
                beginUnlockCountdown()
            } else {
                engageLock()
            }
        }
    }

    func scanTag() {
        if Self.isNFCTestBypassEnabled {
            if hasActiveTrigger {
                releaseLock()
            } else {
                engageLock()
            }
            return
        }

        guard hasPairedTag else {
            popup = .error("Pair your Broke tag before starting a focus session.")
            return
        }
        nfc.scan(successMessage: hasActiveTrigger ? "Broke is unlocking your apps." : "Broke is locking your apps.")
    }

    // MARK: - App-only mode: the thirty second cooling-off period

    /// Starts the wait. The apps stay blocked for the whole countdown — that
    /// pause is the entire product, so it deliberately cannot be skipped.
    func beginUnlockCountdown() {
        guard lockMode == .timer, isManualLocked, unlockCountdown == nil else { return }
        unlockCountdown = UnlockDelay.seconds
        unlockCountdownTask = Task { @MainActor [weak self] in
            while let remaining = self?.unlockCountdown, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                guard let current = self.unlockCountdown else { return }
                self.unlockCountdown = current - 1
            }
            guard !Task.isCancelled, let self, self.unlockCountdown != nil else { return }
            self.unlockCountdown = nil
            self.unlockCountdownTask = nil
            self.releaseLock()
        }
    }

    func cancelUnlockCountdown(userInitiated: Bool = false) {
        guard unlockCountdown != nil else { return }
        unlockCountdownTask?.cancel()
        unlockCountdownTask = nil
        unlockCountdown = nil
        if userInitiated {
            popup = .stayedStrong
        }
    }

#if DEBUG
    /// Debug-only lock toggle that drives the exact same path as an NFC scan,
    /// so banners, haptics, the lock timer, notifications, and shields all stay
    /// consistent. Lets us test the real lock/unlock flow without a tag.
    func debugToggleLock() {
        debugSetLocked(!isManualLocked)
    }

    /// Explicit set, so QA launches don't depend on whatever the last run left
    /// behind in UserDefaults.
    func debugSetLocked(_ locked: Bool) {
        if locked {
            engageLock()
        } else {
            releaseLock()
        }
    }
#endif

#if DEV_BUILD
    /// Dev panel: hand back the emergency unlocks so the exhausted state can be
    /// tested more than once per install.
    func devResetEmergencyUnlocks(to count: Int = 3) {
        emergencyUnlocksRemaining = count
        defaults.set(count, forKey: Key.emergencyUnlocksRemaining)
    }

    /// Dev panel: forget the paired tag so pairing can be walked through again.
    func devForgetPairedTag() {
        defaults.removeObject(forKey: Key.tagID)
        hasPairedTag = false
    }
#endif

    func useEmergencyUnlock() {
        guard isLocked else { return }
        guard emergencyUnlocksRemaining > 0 else {
            popup = .emergencyUnavailable
            return
        }

        emergencyUnlocksRemaining -= 1
        defaults.set(emergencyUnlocksRemaining, forKey: Key.emergencyUnlocksRemaining)

        isManualLocked = false
        cancelUnlockCountdown()
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
        guard podIsInPlay else { return }
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

        // Toggle against what's actually holding the lock, not just the manual
        // flag. In combined mode a tap while the pod has you should read as an
        // unlock attempt (and say so) rather than quietly arming the tag too.
        if hasActiveTrigger {
            releaseLock()
        } else {
            engageLock()
        }
    }

    private func engageLock() {
#if DEBUG
        if !Self.isMascotDemoEnabled {
            guard hasSelection else {
                popup = .error("Your block list is empty. Choose at least one app.")
                return
            }
        }
#else
        guard hasSelection else {
            popup = .error("Your block list is empty. Choose at least one app.")
            return
        }
#endif

        isManualLocked = true
        cancelUnlockCountdown()
#if DEBUG
        if !Self.isMascotDemoEnabled {
            defaults.set(true, forKey: Key.isLocked)
        }
#else
        defaults.set(true, forKey: Key.isLocked)
#endif
        reconcileLockState(showPopup: true)
    }

    private func releaseLock() {
        isManualLocked = false
#if DEBUG
        if !Self.isMascotDemoEnabled {
            defaults.set(false, forKey: Key.isLocked)
        }
#else
        defaults.set(false, forKey: Key.isLocked)
#endif
        if isBLEPodNear && podIsInPlay {
            reconcileLockState(showPopup: false)
            popup = .podStillNear
        } else {
            reconcileLockState(showPopup: true)
        }
    }

    /// Only the trigger belonging to the chosen mode is allowed to lock. A tag
    /// user walking past someone else's pod should not get blocked, and an
    /// app-only user has no hardware in the loop at all.
    ///
    /// Combined mode is deliberately an OR: either piece of hardware can lock
    /// you, so getting back out needs both of them to agree.
    private var hasActiveTrigger: Bool {
        switch lockMode {
        case .tag, .timer: isManualLocked
        case .pod: isBLEPodNear
        case .both: isManualLocked || isBLEPodNear
        }
    }

    /// Whether the pod is allowed to drive the lock in the chosen mode.
    private var podIsInPlay: Bool {
        lockMode == .pod || lockMode == .both
    }

    private func reconcileLockState(showPopup: Bool) {
        let hasActiveTrigger = self.hasActiveTrigger
        var shouldLock = hasSelection && hasActiveTrigger && hasScreenTimeAuthorization
#if DEBUG
        if Self.isMascotDemoEnabled {
            shouldLock = isManualLocked
        }
#endif

        if shouldLock {
            applyShields()
        } else {
#if DEBUG && targetEnvironment(simulator)
            if !Self.isMascotDemoEnabled {
                store.clearAllSettings()
            }
#else
            store.clearAllSettings()
#endif
        }

#if DEBUG
        if !Self.isMascotDemoEnabled,
           hasActiveTrigger && hasSelection && !hasScreenTimeAuthorization {
            isLocked = false
            updateDisplayedLockStateImmediately(false)
            if showPopup {
                popup = .screenTimeRequired
            }
            return
        }
#else
        if hasActiveTrigger && hasSelection && !hasScreenTimeAuthorization {
            isLocked = false
            updateDisplayedLockStateImmediately(false)
            if showPopup {
                popup = .screenTimeRequired
            }
            return
        }
#endif

        guard shouldLock != isLocked else { return }
        let previousLockState = isLocked
        isLocked = shouldLock
        updateLockTimer(for: shouldLock)
        sendLockNotification(isLocked: shouldLock)
        scheduleLockFeedback(from: previousLockState, to: shouldLock)
    }

    private func applyShields() {
#if DEBUG && targetEnvironment(simulator)
        guard !Self.isMascotDemoEnabled else { return }
#endif
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

    /// Deferred until the user reaches the main app — asking during the
    /// welcome screen interrupts onboarding before they know what Broke is.
    func requestNotificationAuthorizationIfNeeded() {
#if DEBUG
        // QA launches never answer the system prompt, so it would sit on screen
        // across relaunches and cover every screenshot.
        // Keyed off the explicit hooks, not the simulator stand-in: an ordinary
        // dev run on the simulator should still see the real prompt.
        let env = ProcessInfo.processInfo.environment
        if env["FAKE_SELECTION"] == "1" || env["ONBOARD_STEP"] != nil { return }
#endif
        guard !hasRequestedNotifications else { return }
        hasRequestedNotifications = true
        requestNotificationAuthorization()
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
        // Only notify when Broke is not in the foreground; while the app is
        // open the mascot, badge, timer, and haptics already convey the change.
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = isLocked ? "Broke is on duty" : "You're free to roam"
        content.body = isLocked
            ? "Your picked apps are off the table. Go do something with your hands."
            : "Your apps are back. Try not to make us regret it."
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
        isLocked ? "Broke is on duty" : "You're free to roam"
    }

    var message: String {
        isLocked
            ? "Your picked apps are off the table."
            : "Your apps are back. Use them wisely."
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
    case stayedStrong
    case error(String)

    var id: String {
        switch self {
        case .tagReady: "tagReady"
        case .wrongTag: "wrongTag"
        case .podStillNear: "podStillNear"
        case .screenTimeRequired: "screenTimeRequired"
        case .emergencyUnlocked(let remaining): "emergencyUnlocked-\(remaining)"
        case .emergencyUnavailable: "emergencyUnavailable"
        case .stayedStrong: "stayedStrong"
        case .error(let message): "error-\(message)"
        }
    }

    var title: String {
        switch self {
        case .tagReady: "Tag paired."
        case .wrongTag: "Wrong tag."
        case .podStillNear: "Your pod says no."
        case .screenTimeRequired: "One permission short."
        case .emergencyUnlocked: "Emergency unlock used."
        case .emergencyUnavailable: "That was the last one."
        case .stayedStrong: "Nice save."
        case .error: "That didn't work."
        }
    }

    var message: String {
        switch self {
        case .tagReady:
            "This tag runs the lock now. Tap to lock, tap again to unlock. Losing it is a you problem."
        case .wrongTag:
            "Not your tag. Broke only answers to the one you paired."
        case .podStillNear:
            "Lock's off, but you're still in the pod's room. Walk away and your apps come back."
        case .screenTimeRequired:
            "iOS hasn't granted Screen Time access yet. Turn it on and we're in business."
        case .emergencyUnlocked(let remaining):
            "\(remaining) left, and they don't come back. Spend them like you mean it."
        case .emergencyUnavailable:
            "All three are gone. Honest way from here."
        case .stayedStrong:
            "Countdown called off, streak intact. Most people do."
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
        case .stayedStrong: "hand.thumbsup.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .tagReady, .emergencyUnlocked, .stayedStrong:
            Color(red: 0.08, green: 0.46, blue: 0.3)
        case .wrongTag, .podStillNear, .screenTimeRequired, .emergencyUnavailable, .error:
            Color(red: 0.83, green: 0.24, blue: 0.17)
        }
    }

    var buttonTitle: String {
        switch self {
        case .tagReady: "LET'S GO"
        case .podStillNear: "FAIR ENOUGH"
        case .screenTimeRequired: "ENABLE ACCESS"
        case .emergencyUnlocked: "OK"
        case .stayedStrong: "PROUD OF ME"
        case .wrongTag, .emergencyUnavailable, .error: "TRY AGAIN"
        }
    }
}
