//
//  BrokeApp.swift
//  Broke
//
//  Created by Hans Vador on 6/8/26.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct BrokeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var designSettings = DesignSettings()
    @AppStorage("brokeHasOnboarded") private var hasOnboarded = false
#if DEBUG
    private let isMascotDemoEnabled = ProcessInfo.processInfo.environment["MASCOT_DEMO"] == "1"
    private let mascotPreviewState = ProcessInfo.processInfo.environment["MASCOT_PREVIEW"]
        .flatMap(MascotState.init(rawValue:))
    // Deterministic single-fruit preview for QA (bypasses the mascot picker):
    // launch with SIMCTL_CHILD_MASCOT_FRUIT=<fruit> to render that fruit's idle rig.
    private let mascotFruitPreview = ProcessInfo.processInfo.environment["MASCOT_FRUIT"]
        .flatMap(FruitKind.init(rawValue:))
#endif

    var body: some Scene {
        WindowGroup {
            rootView
            .environmentObject(designSettings)
            .onOpenURL { url in
                coordinator.model.handleIncomingTagURL(url)
            }
#if DEV_BUILD
            // The badge doubles as the dev panel's entry point, so the QA hooks
            // are reachable when the app is launched by tapping its icon — the
            // environment variables only arrive from the simulator or Xcode.
            .devTools(
                model: coordinator.model,
                proximity: coordinator.proximity,
                designSettings: designSettings
            )
#else
            .devBuildBadge()
#endif
        }
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if isMascotDemoEnabled {
            contentView
                .task {
                    await runMascotDemo()
                }
        } else if let mascotFruitPreview {
            ZStack {
                Color(white: 0.93).ignoresSafeArea()
                LottieMascotView(
                    fruit: mascotFruitPreview,
                    state: mascotPreviewState ?? .idle
                )
                .frame(width: 320, height: 320)
            }
        } else if let mascotPreviewState {
            MascotPreviewView(state: mascotPreviewState)
        } else {
            gatedContent
        }
#else
        gatedContent
#endif
    }

    /// Onboarding owns the first launch; after that it never appears again.
    @ViewBuilder
    private var gatedContent: some View {
#if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["ONBOARD_STEP"] != nil {
            onboardingView
        } else if hasOnboarded || env["FORCE_MODE"] != nil {
            contentView
        } else {
            onboardingView
        }
#else
        if hasOnboarded {
            contentView
        } else {
            onboardingView
        }
#endif
    }

    private var onboardingView: some View {
        OnboardingView(
            model: coordinator.model,
            proximity: coordinator.proximity
        ) {
            withAnimation(.easeInOut(duration: 0.35)) { hasOnboarded = true }
        }
        .environment(\.designTokens, designSettings.tokens)
        .transition(.opacity)
    }

    private var contentView: some View {
        ContentView(
            model: coordinator.model,
            proximity: coordinator.proximity
        )
#if DEBUG
        .task {
            // QA hooks so the simulator can reach states that normally need a
            // tag tap or a 30 second wait.
            let env = ProcessInfo.processInfo.environment
            guard env["DEBUG_LOCKED"] == "1" || env["DEBUG_COUNTDOWN"] == "1" else { return }
            try? await Task.sleep(for: .milliseconds(400))
            coordinator.model.debugSetLocked(true)
            if env["DEBUG_COUNTDOWN"] == "1" {
                try? await Task.sleep(for: .milliseconds(900))
                coordinator.model.beginUnlockCountdown()
            }
        }
#endif
    }

#if DEBUG
    @MainActor
    private func runMascotDemo() async {
        // FocusLockModel initializes demo launches unlocked, so the real status
        // card gets a full idle beat before the first production-path toggle.
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                coordinator.model.debugToggleLock()

                try await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                coordinator.model.debugToggleLock()
            } catch {
                return
            }
        }
    }
#endif
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Suppress any foreground presentation: lock/unlock notifications are
        // only meant for when Broke is backgrounded or inactive.
        []
    }
}
