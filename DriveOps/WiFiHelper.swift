//
//  WiFiHelper.swift
//  DriveOps
//

import Foundation
import Combine
import NetworkExtension
import SystemConfiguration.CaptiveNetwork

@MainActor
class WiFiHelper: ObservableObject {
    @Published var currentSSID: String?
    @Published var isLoading = false

    var looksLikeOBD: Bool {
        guard let ssid = currentSSID?.lowercased() else { return false }
        let obdKeywords = ["obd", "elm", "vlink", "v-link", "veepeak", "carista", "konnwei", "icar", "vgate"]
        return obdKeywords.contains { ssid.contains($0) }
    }

    func refresh() {
        isLoading = true
        #if os(iOS)
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            Task { @MainActor in
                self?.currentSSID = network?.ssid
                self?.isLoading = false
            }
        }
        #else
        currentSSID = nil
        isLoading = false
        #endif
    }
}
