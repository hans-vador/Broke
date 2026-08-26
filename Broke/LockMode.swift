import Foundation
import SwiftUI

/// How this phone locks and unlocks Broke.
///
/// Chosen once, during onboarding, and then permanent — the whole point of
/// Broke is that you can't renegotiate the deal with yourself at 1am. Broke
/// works with hardware or without it; the mode just decides which.
enum LockMode: String, CaseIterable, Identifiable, Codable {
    /// Tap a paired NFC tag to flip the lock.
    case tag
    /// A BLE pod blocks automatically whenever you're in its room.
    case pod
    /// Both pieces of hardware at once. Either one can lock you; getting back
    /// out means both of them have to agree.
    case both
    /// No hardware. Lock from the app; unlocking makes you wait it out.
    case timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tag: "NFC Tag"
        case .pod: "Room Pod"
        case .both: "Tag + Pod"
        case .timer: "Just the App"
        }
    }

    var tagline: String {
        switch self {
        case .tag: "Tap to lock and unlock"
        case .pod: "Locks while you're in the room"
        case .both: "Tag and pod together"
        case .timer: "No hardware needed"
        }
    }

    var blurb: String {
        switch self {
        case .tag:
            "Keep the tag somewhere away from your desk. Tap it to lock your apps, tap it again to unlock."
        case .pod:
            "Keep the pod in the room you work in. Your apps lock while you are in range and unlock when you leave."
        case .both:
            "Either the tag or the pod can lock your apps. Both have to agree before they unlock."
        case .timer:
            "Lock from the app. Unlocking takes 30 seconds."
        }
    }

    var symbol: String {
        switch self {
        case .tag: "wave.3.right"
        case .pod: "sensor.tag.radiowaves.forward"
        case .both: "lock.shield.fill"
        case .timer: "hourglass"
        }
    }

    var requiresHardware: Bool { self != .timer }

    /// One-liner shown on the home screen under the status card.
    var homeHint: String {
        switch self {
        case .tag: "Only your paired tag can unlock this."
        case .pod: "Your apps unlock when you leave the pod's room."
        case .both: "Either one locks your apps. Both have to agree to unlock."
        case .timer: "Unlocking takes 30 seconds."
        }
    }
}

/// The mode is a one-time decision, so it is written once and then defended.
enum LockModeStore {
    private static let key = "brokeLockMode"
    private static let onboardedKey = "brokeHasOnboarded"

    static var current: LockMode? {
#if DEBUG
        // QA hook: launch with FORCE_MODE=<tag|pod|both|timer> to preview a mode
        // without re-running onboarding.
        if let forced = ProcessInfo.processInfo.environment["FORCE_MODE"],
           let mode = LockMode(rawValue: forced) {
            return mode
        }
#endif
        return UserDefaults.standard.string(forKey: key).flatMap(LockMode.init(rawValue:))
    }

    /// Persists the choice. Silently refuses to overwrite an existing one —
    /// this is deliberately not re-configurable from anywhere in the app.
    @discardableResult
    static func commit(_ mode: LockMode) -> Bool {
        guard current == nil else { return false }
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        return true
    }

    static var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardedKey) }
    }

#if DEBUG
    /// Debug-only: wipes the permanent choice so onboarding can be re-run.
    static func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: onboardedKey)
    }
#endif
}

/// How long you have to sit with the decision before app-only mode unlocks.
enum UnlockDelay {
    static let seconds = 30
}
