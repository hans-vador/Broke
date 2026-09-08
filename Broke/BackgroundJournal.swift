//
//  BackgroundJournal.swift
//  Broke
//
//  A tiny persisted ring buffer of timestamped events, kept to answer one
//  question from the phone itself: did Broke wake up and act while it was
//  not on screen?
//
//  iOS gives no way to watch this live — the whole point is that the app is
//  not running where you can see it — so the app writes a line whenever the
//  radio wakes it, a pod crosses the boundary, or the lock changes state.
//  The dev panel renders the log; recording costs microseconds and a few KB,
//  so it is always on in every build.
//

import Foundation
import UIKit

@MainActor
enum BackgroundJournal {
    private static let key = "backgroundJournal"
    private static let capacity = 200

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm:ss"
        return formatter
    }()

    /// Records one event with a timestamp and whether the app was on screen.
    /// The foreground/background tag is the payload: "[bg]" lines are proof
    /// the app acted without being open.
    static func record(_ event: String) {
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "fg"
        case .background: state = "bg"
        case .inactive: state = "inactive"
        @unknown default: state = "?"
        }

        let defaults = UserDefaults.standard
        var entries = defaults.stringArray(forKey: key) ?? []
        entries.append("\(clock.string(from: Date())) [\(state)] \(event)")
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        defaults.set(entries, forKey: key)
    }

    /// Newest first.
    static var entries: [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).reversed()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
