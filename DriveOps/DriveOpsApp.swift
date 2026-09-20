//
//  DriveOpsApp.swift
//  DriveOps
//

import SwiftUI

@main
struct DriveOpsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: Binding(
                    get: { !hasSeenWelcome },
                    set: { if !$0 { hasSeenWelcome = true } }
                )) {
                    WelcomeFlowView(isPresented: Binding(
                        get: { !hasSeenWelcome },
                        set: { if !$0 { hasSeenWelcome = true } }
                    ))
                    .interactiveDismissDisabled()
                }
        }
    }
}
