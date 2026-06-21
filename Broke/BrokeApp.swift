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

    var body: some Scene {
        WindowGroup {
            ContentView(
                model: coordinator.model,
                proximity: coordinator.proximity
            )
            .environmentObject(designSettings)
            .onOpenURL { url in
                coordinator.model.handleIncomingTagURL(url)
            }
        }
    }
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
        [.banner, .list, .sound]
    }
}
