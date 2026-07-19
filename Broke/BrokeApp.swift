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
#if DEBUG
    private let isMascotDemoEnabled = ProcessInfo.processInfo.environment["MASCOT_DEMO"] == "1"
    private let mascotPreviewState = ProcessInfo.processInfo.environment["MASCOT_PREVIEW"]
        .flatMap(MascotState.init(rawValue:))
#endif

    var body: some Scene {
        WindowGroup {
            rootView
            .environmentObject(designSettings)
            .onOpenURL { url in
                coordinator.model.handleIncomingTagURL(url)
            }
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
        } else if let mascotPreviewState {
            MascotPreviewView(state: mascotPreviewState)
        } else {
            contentView
        }
#else
        contentView
#endif
    }

    private var contentView: some View {
        ContentView(
            model: coordinator.model,
            proximity: coordinator.proximity
        )
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
