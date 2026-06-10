//
//  BrokeApp.swift
//  Broke
//
//  Created by Hans Vador on 6/8/26.
//

import SwiftUI

@main
struct BrokeApp: App {
    var body: some Scene {
        WindowGroup {
#if targetEnvironment(simulator)
            SimulatorDemoView()
#else
            ContentView()
#endif
        }
    }
}
