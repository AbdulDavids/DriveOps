//
//  AppDelegate.swift
//  DriveOps
//
//  A UISceneSession-owning delegate is required to advertise the CarPlay
//  scene configuration declared in Info.plist — SwiftUI's plain `App`
//  lifecycle has no hook for that, so this bridges in via
//  @UIApplicationDelegateAdaptor in DriveOpsApp.
//

import CarPlay
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
