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
        case .tag: "Tap to commit"
        case .pod: "Walk in, get blocked"
        case .both: "The full setup"
        case .timer: "No hardware needed"
        }
    }

    var blurb: String {
        switch self {
        case .tag:
            "Stick it somewhere annoying — desk, fridge, gym bag. Tap to lock, tap to unlock. No tag, no temptation."
        case .pod:
            "Leave it in the room you actually work in. Walk in, your apps lock. Walk out, they come back."
        case .both:
            "The pod holds the room, the tag covers everywhere else. Either one locks you. Both have to let you go."
        case .timer:
            "Lock from the app. Unlocking costs thirty seconds of sitting with it — usually long enough to change your mind."
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
        case .tag: "Only your paired tag can flip this lock."
        case .pod: "Apps follow the pod. Leave the room to get them back."
        case .both: "Tag or pod, either one locks you. Both have to let you go."
        case .timer: "Unlocking takes thirty seconds. On purpose."
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
