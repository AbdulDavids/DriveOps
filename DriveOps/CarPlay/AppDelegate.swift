//
//  AppDelegate.swift
//  DriveOps
//
//  CarPlay support is paused: the com.apple.developer.carplay-parking
//  entitlement it needs requires Apple's approval before it can be included
//  in a provisioning profile at all, and Xcode refuses to build for a device
//  with it present but unapproved. CarPlaySceneDelegate.swift is left in
//  place, just not registered here — re-add the CPTemplateApplicationScene
//  branch and the entitlement once Apple grants access.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
