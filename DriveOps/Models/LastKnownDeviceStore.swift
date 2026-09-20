//
//  LastKnownDeviceStore.swift
//  DriveOps
//
//  Remembers the last Bluetooth adapter the user successfully connected to,
//  so the app can try to reconnect to it automatically on the next launch
//  instead of always waiting for a manual pick from BLEDevicePickerSheet.
//

import Foundation

enum LastKnownDeviceStore {
    private static let key = "lastKnownBLEDeviceIdentifier"

    static func load() -> UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init)
    }

    static func save(_ identifier: UUID) {
        UserDefaults.standard.set(identifier.uuidString, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
