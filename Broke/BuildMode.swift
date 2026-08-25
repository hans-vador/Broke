//
//  BuildMode.swift
//  Broke
//
//  Which flavour of the app is running: the development build (own bundle ID,
//  QA hooks, installs side by side) or the shipped build (exactly what ships).
//  The mode is fixed at compile time by the DEV_BUILD flag, which the Debug
//  configuration sets and Release does not.
//

import Foundation
import SwiftUI

enum AppBuild {
    enum Mode {
        case development
        case shipped
    }

    static let mode: Mode = {
#if DEV_BUILD
        .development
#else
        .shipped
#endif
    }()

    /// True only in the development app. Prefer this over `#if DEBUG` for
    /// behaviour that should track the dev/shipped split rather than the
    /// compiler's optimisation level.
    static var isDevelopment: Bool { mode == .development }

    /// Bundle identifier of the running app — `dev.kunjadia.broke.dev` in
    /// development, `dev.kunjadia.broke` when shipped.
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    /// Home-screen name: "Broke Dev" or "Broke".
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Broke"
    }

    /// URL scheme this build answers to — `brokedev://` or `broke://`.
    static var urlScheme: String {
        isDevelopment ? "brokedev" : "broke"
    }

    /// One-line summary for logs and the dev badge.
    static var summary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(displayName) \(version) (\(build)) · \(bundleIdentifier)"
    }
}

extension View {
    /// Marks the development app with a small corner badge so a dev build is
    /// never mistaken for the shipped one. Compiled out of shipped builds.
    func devBuildBadge() -> some View {
        modifier(DevBuildBadge())
    }
}

private struct DevBuildBadge: ViewModifier {
    func body(content: Content) -> some View {
#if DEV_BUILD
        content.overlay(alignment: .topTrailing) {
            Text("DEV")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.85), in: Capsule())
                .padding(.trailing, 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
#else
        content
#endif
    }
}
