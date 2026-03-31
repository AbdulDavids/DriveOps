//
//  OBDViewModel.swift
//  DriveOps
//

import Foundation
import Combine
import SwiftOBD2

@MainActor
class OBDViewModel: ObservableObject {
    private let obdService = OBDService(connectionType: .bluetooth)

    @Published var connectionState: ConnectionState = .disconnected
    @Published var obdInfo: OBDInfo?
    @Published var liveData: [String: String] = [:]
    @Published var errorMessage: String?
    @Published var isConnecting = false
    @Published var logs: [String] = []

    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?

    init(bindServiceState: Bool = true) {
        if bindServiceState {
            obdService.$connectionState
                .receive(on: DispatchQueue.main)
                .assign(to: &$connectionState)
        }
    }

    private func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(ts)] \(message)")
    }

    func connect() {
        isConnecting = true
        errorMessage = nil
        log("Scanning for Bluetooth adapter…")
        Task {
            do {
                let info = try await obdService.startConnection()
                self.obdInfo = info
                self.isConnecting = false
                self.log("Connected. Protocol: \(info.obdProtocol?.description ?? "unknown"), VIN: \(info.vin ?? "n/a"), PIDs: \(info.supportedPIDs?.count ?? 0)")
                self.startLiveData()
            } catch {
                self.log("Connection failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.isConnecting = false
            }
        }
    }

    func connectDemo() {
        isConnecting = true
        errorMessage = nil
        log("Starting demo connection…")
        let demoService = OBDService(connectionType: .demo)
        Task {
            do {
                let info = try await demoService.startConnection()
                self.obdInfo = info
                self.isConnecting = false
                self.log("Demo connected. Protocol: \(info.obdProtocol?.description ?? "unknown"), VIN: \(info.vin ?? "n/a"), PIDs: \(info.supportedPIDs?.count ?? 0)")
                self.startLiveDataWith(demoService)
            } catch {
                self.log("Demo connection failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.isConnecting = false
            }
        }
    }

    private func startLiveData() {
        startLiveDataWith(obdService)
    }

    private func startLiveDataWith(_ service: OBDService) {
        // Note: .fuelLevel is excluded — the library's mock response passes a Double
        // to a %02X format specifier, crashing String(format:) on every poll.
        // .controlModuleVoltage has no mock response at all.
        let pids: [OBDCommand] = [
            .mode1(.rpm),
            .mode1(.speed),
            .mode1(.coolantTemp),
            .mode1(.throttlePos),
            .mode1(.engineLoad),
            .mode1(.intakeTemp),
            .mode1(.maf),
            .mode1(.barometricPressure),
            .mode1(.intakePressure),
            .mode1(.timingAdvance),
        ]

        log("Starting live data poll for \(pids.count) PIDs…")
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let results = try await service.requestPIDs(pids, unit: .metric)
                    if results.isEmpty {
                        self.log("⚠️ Empty batch")
                    }
                    var updated = self.liveData
                    for (cmd, measurement) in results {
                        updated[cmd.properties.description] = "\((measurement.value * 10).rounded() / 10) \(measurement.unit.symbol)"
                    }
                    self.liveData = updated
                } catch {
                    if !Task.isCancelled {
                        self.log("Poll error: \(error.localizedDescription)")
                        self.errorMessage = error.localizedDescription
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    func disconnect() {
        log("Disconnecting…")
        pollTask?.cancel()
        pollTask = nil
        obdService.stopConnection()
        obdInfo = nil
        liveData = [:]
    }
}
