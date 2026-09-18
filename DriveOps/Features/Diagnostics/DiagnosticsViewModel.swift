//
//  DiagnosticsViewModel.swift
//  DriveOps
//

import Foundation
import SwiftOBD2
import os

extension OBDViewModel {
    func scanTroubleCodes() {
        isScanningCodes = true
        troubleCodes = [:]
        scanError = nil
        log("DTC scan started (\(activeConnectionType?.rawValue ?? "unknown"))")

        if activeConnectionType == .demo {
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self.troubleCodes = Self.demoDTCs
                self.isScanningCodes = false
                let total = Self.demoDTCs.values.map(\.count).reduce(0, +)
                self.log("DTC scan: \(total) code(s) found across \(Self.demoDTCs.count) ECU(s)")
            }
            return
        }

        guard let service = activeService else {
            log("Diagnostics: not connected")
            isScanningCodes = false
            return
        }

        let startedAt = Date()
        Task {
            do {
                let result = try await service.scanForTroubleCodes()
                let elapsed = Date().timeIntervalSince(startedAt)
                self.troubleCodes = result
                self.isScanningCodes = false
                let total = result.values.map(\.count).reduce(0, +)
                self.log("DTC scan: \(total) code(s) found across \(result.count) ECU(s) in \(String(format: "%.2f", elapsed))s")
                AppLogger.diagnostics.info("scanForTroubleCodes total=\(total) ecus=\(result.count) elapsed=\(elapsed, format: .fixed(precision: 2))s")
            } catch {
                let elapsed = Date().timeIntervalSince(startedAt)
                self.scanError = error.localizedDescription
                self.isScanningCodes = false
                self.log("DTC scan failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
                AppLogger.diagnostics.error("scanForTroubleCodes failed elapsed=\(elapsed, format: .fixed(precision: 2))s error=\(String(describing: error), privacy: .public)")
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
        guard let service = activeService else {
            log("Diagnostics: clear requested but not connected")
            return
        }
        let previousCount = troubleCodes.values.map(\.count).reduce(0, +)
        log("Clearing \(previousCount) DTC(s)…")
        isScanningCodes = true
        Task {
            do {
                try await service.clearTroubleCodes()
                self.troubleCodes = [:]
                self.isScanningCodes = false
                self.log("DTCs cleared (\(previousCount) removed)")
                AppLogger.diagnostics.info("clearTroubleCodes success cleared=\(previousCount)")
            } catch {
                self.scanError = error.localizedDescription
                self.isScanningCodes = false
                self.log("DTC clear failed: \(error.localizedDescription)")
                AppLogger.diagnostics.error("clearTroubleCodes failed error=\(String(describing: error), privacy: .public)")
            }
        }
    }
}
