//
//  WiFiHelper.swift
//  DriveOps
//

import Foundation

@MainActor
class WiFiHelper: ObservableObject {
    @Published var currentSSID: String?
    @Published var ssidUnavailable = false

    var looksLikeOBD: Bool {
        guard let ssid = currentSSID?.lowercased() else { return false }
        let obdKeywords = ["obd", "elm", "vlink", "v-link", "veepeak", "carista", "konnwei", "icar", "vgate"]
        return obdKeywords.contains { ssid.contains($0) }
    }

    func refresh() {
        // Access WiFi Information entitlement requires a paid developer account.
        // For now, we skip SSID detection and just show the setup guide.
        currentSSID = nil
        ssidUnavailable = true
    }
}
