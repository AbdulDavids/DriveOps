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

        if activeConnectionType == .demo {
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self.troubleCodes = Self.demoDTCs
                self.isScanningCodes = false
                let total = Self.demoDTCs.values.map(\.count).reduce(0, +)
                self.log("DTC scan: \(total) code(s) found")
            }
            return
        }

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

    private static let demoDTCs: [ECUID: [TroubleCode]] = {
        func codes(_ pairs: [(String, String)]) -> [TroubleCode] {
            pairs.compactMap { try? JSONDecoder().decode(TroubleCode.self,
                from: Data("{\"code\":\"\($0.0)\",\"description\":\"\($0.1)\"}".utf8)) }
        }
        return [
            .engine: codes([
                ("P0171", "System Too Lean (Bank 1)"),
                ("P0300", "Random/Multiple Cylinder Misfire Detected"),
                ("P0420", "Catalyst System Efficiency Below Threshold (Bank 1)"),
                ("P0442", "Evaporative Emission System Leak Detected (Small Leak)"),
                ("P0128", "Coolant Temperature Below Thermostat Regulating Temperature"),
            ]),
            .transmission: codes([
                ("P0700", "Transmission Control System Malfunction"),
                ("P0741", "Torque Converter Clutch Circuit Performance or Stuck Off"),
            ]),
            .unknown: codes([
                ("C0035", "Left Front Wheel Speed Sensor Circuit"),
                ("U0100", "Lost Communication With ECM/PCM"),
                ("U0207", "Lost Communication With Hybrid Battery Control Module"),
            ]),
        ]
    }()

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
