//
//  DiagnosticsViewModel.swift
//  DriveOps
//

import Foundation
import SwiftOBD2

extension OBDViewModel {
    func scanTroubleCodes() {
        guard let service = activeService else {
            log("Diagnostics: not connected")
            return
        }
        isScanningCodes = true
        troubleCodes = [:]
        scanError = nil
        Task {
            do {
                let result = try await service.scanForTroubleCodes()
                self.troubleCodes = result
                self.isScanningCodes = false
                let total = result.values.map(\.count).reduce(0, +)
                self.log("DTC scan: \(total) code(s) found")
            } catch {
                self.scanError = error.localizedDescription
                self.isScanningCodes = false
                self.log("DTC scan failed: \(error.localizedDescription)")
            }
        }
    }

    func clearTroubleCodes() {
        guard let service = activeService else { return }
        isScanningCodes = true
        Task {
            do {
                try await service.clearTroubleCodes()
                self.troubleCodes = [:]
                self.isScanningCodes = false
                self.log("DTCs cleared")
            } catch {
                self.scanError = error.localizedDescription
                self.isScanningCodes = false
                self.log("DTC clear failed: \(error.localizedDescription)")
            }
        }
    }
}
