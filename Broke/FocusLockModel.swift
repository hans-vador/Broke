import Combine
import FamilyControls
import ManagedSettings
import SwiftUI

@MainActor
final class FocusLockModel: ObservableObject {
    static let isNFCTestBypassEnabled = true

    @Published var selection: FamilyActivitySelection {
        didSet {
            saveSelection()
            if isLocked {
                applyShields()
            }
        }
    }
    @Published private(set) var isLocked: Bool
    @Published private(set) var hasPairedTag: Bool
    @Published var popup: FocusPopup?

    private let store = ManagedSettingsStore(named: .init("BrokeFocus"))
    private let nfc = NFCService()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let selection = "focusSelection"
        static let isLocked = "focusIsLocked"
        static let tagID = "focusTagID"
    }

    init() {
        if let data = defaults.data(forKey: Key.selection),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        } else {
            selection = FamilyActivitySelection()
        }

        isLocked = defaults.bool(forKey: Key.isLocked)
        hasPairedTag = defaults.string(forKey: Key.tagID) != nil

        if isLocked {
            applyShields()
        }

        nfc.onRead = { [weak self] payload in
            Task { @MainActor in
                self?.handleScannedPayload(payload)
            }
        }
        nfc.onWrite = { [weak self] payload in
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
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var hasSelection: Bool {
        selectedItemCount > 0
    }

    var canScan: Bool {
        if Self.isNFCTestBypassEnabled {
            return hasSelection
        }
        return hasSelection && hasPairedTag && NFCService.isAvailable
    }

    var footerMessage: String {
        if Self.isNFCTestBypassEnabled {
            return "Test mode: NFC is disabled. Use the button to lock and unlock."
        }
        if !NFCService.isAvailable {
            return "NFC scanning requires a supported physical iPhone."
        }
        if !hasSelection {
            return "Choose at least one app before setting up your tag."
        }
        if !hasPairedTag {
            return "Set up a writable NDEF tag to create your focus key."
        }
        return "Only your paired NDEF tag can change this lock."
    }

    func requestAuthorizationIfNeeded() async {
#if targetEnvironment(simulator)
        return
#else
        guard AuthorizationCenter.shared.authorizationStatus != .approved else { return }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            popup = .error("Screen Time access is required to block your selected apps.")
        }
#endif
    }

    func writeTag() {
        guard hasSelection else {
            popup = .error("Choose the apps you want to block first.")
            return
        }

        let payload = "broke://focus/\(UUID().uuidString.lowercased())"
        nfc.write(payload: payload)
    }

    func scanTag() {
        if Self.isNFCTestBypassEnabled {
            if isLocked {
                unlock()
            } else {
                lock()
            }
            return
        }

        guard hasPairedTag else {
            popup = .error("Set up your NFC tag before starting a focus session.")
            return
        }
        nfc.scan()
    }

    func updateBLEProximity(isNear: Bool) {
        guard hasSelection else { return }
        if isNear && !isLocked {
            lock()
        } else if !isNear && isLocked {
            unlock()
        }
    }

    private func handleScannedPayload(_ payload: String) {
        guard payload == defaults.string(forKey: Key.tagID) else {
            popup = .wrongTag
            return
        }

        if isLocked {
            unlock()
        } else {
            lock()
        }
    }

    private func lock() {
        guard hasSelection else {
            popup = .error("Your block list is empty. Choose at least one app.")
            return
        }

        applyShields()
        isLocked = true
        defaults.set(true, forKey: Key.isLocked)
        popup = .locked
    }

    private func unlock() {
        store.clearAllSettings()
        isLocked = false
        defaults.set(false, forKey: Key.isLocked)
        popup = .unlocked
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

    private func saveSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Key.selection)
    }
}

enum FocusPopup: Identifiable {
    case locked
    case unlocked
    case tagReady
    case wrongTag
    case error(String)

    var id: String {
        switch self {
        case .locked: "locked"
        case .unlocked: "unlocked"
        case .tagReady: "tagReady"
        case .wrongTag: "wrongTag"
        case .error(let message): "error-\(message)"
        }
    }

    var title: String {
        switch self {
        case .locked: "You are locked in."
        case .unlocked: "Welcome back."
        case .tagReady: "Tag is ready."
        case .wrongTag: "Not your key."
        case .error: "Something went wrong."
        }
    }

    var message: String {
        switch self {
        case .locked:
            "Your selected apps are now blocked. Put the tag somewhere intentional and go do the thing."
        case .unlocked:
            "Your apps are available again. Nice work making a little room for your attention."
        case .tagReady:
            "Your unique NDEF focus key was written successfully. Scan it whenever you want to lock or unlock."
        case .wrongTag:
            "This NFC tag does not match the one paired with Broke. Find your original focus tag and try again."
        case .error(let message):
            message
        }
    }

    var symbol: String {
        switch self {
        case .locked: "lock.fill"
        case .unlocked: "sparkles"
        case .tagReady: "checkmark.seal.fill"
        case .wrongTag: "key.slash.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .locked: Color(red: 0.91, green: 0.25, blue: 0.13)
        case .unlocked, .tagReady: Color(red: 0.08, green: 0.46, blue: 0.3)
        case .wrongTag, .error: Color(red: 0.83, green: 0.24, blue: 0.17)
        }
    }

    var buttonTitle: String {
        switch self {
        case .locked: "LET'S FOCUS"
        case .unlocked: "DONE"
        case .tagReady: "GOT IT"
        case .wrongTag, .error: "TRY AGAIN"
        }
    }
}
