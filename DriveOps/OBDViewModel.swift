//
//  OBDViewModel.swift
//  DriveOps
//

import Foundation
import Combine
import SwiftOBD2

@MainActor
class OBDViewModel: ObservableObject {
    private let bluetoothService = OBDService(connectionType: .bluetooth)
    private var activeService: OBDService?

    @Published var connectionState: ConnectionState = .disconnected
    @Published var obdInfo: OBDInfo?
    @Published var liveData: [String: String] = [:]
    @Published var errorMessage: String?
    @Published var isConnecting = false
    @Published var activeConnectionType: ConnectionType?
    @Published var logs: [String] = []

    private var cancellables = Set<AnyCancellable>()
    private var connectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init(bindServiceState: Bool = true) {
        if bindServiceState {
            bluetoothService.$connectionState
                .receive(on: DispatchQueue.main)
                .assign(to: &$connectionState)
        }
    }

    // MARK: - Logging

    func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(ts)] \(message)")
    }

    // MARK: - Connection

    func connect() {
        startConnecting(type: .bluetooth, service: bluetoothService)
    }

    func connectWifi() {
        startConnecting(type: .wifi, service: OBDService(connectionType: .wifi))
    }

    func connectDemo() {
        startConnecting(type: .demo, service: OBDService(connectionType: .demo))
    }

    func cancelConnection() {
        log("Connection cancelled.")
        connectTask?.cancel()
        connectTask = nil
        activeService?.stopConnection()
        activeService = nil
        isConnecting = false
        activeConnectionType = nil
        connectionState = .disconnected
    }

    func disconnect() {
        log("Disconnecting…")
        pollTask?.cancel()
        pollTask = nil
        activeService?.stopConnection()
        activeService = nil
        connectionState = .disconnected
        activeConnectionType = nil
        obdInfo = nil
        liveData = [:]
    }

    private func startConnecting(type: ConnectionType, service: OBDService) {
        isConnecting = true
        activeConnectionType = type
        errorMessage = nil
        log("Connecting via \(type.rawValue)…")
        bind(service)
        connectTask = Task {
            do {
                let info = try await service.startConnection()
                guard !Task.isCancelled else { return }
                self.obdInfo = info
                self.isConnecting = false
                self.connectTask = nil
                self.log("Connected via \(type.rawValue). Protocol: \(info.obdProtocol?.description ?? "unknown"), VIN: \(info.vin ?? "n/a"), PIDs: \(info.supportedPIDs?.count ?? 0)")
                self.startLiveDataWith(service)
            } catch {
                guard !Task.isCancelled else { return }
                self.log("\(type.rawValue) connection failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.isConnecting = false
                self.activeConnectionType = nil
                self.connectTask = nil
            }
        }
    }

    // MARK: - Private

    private func bind(_ service: OBDService) {
        activeService = service
        cancellables.removeAll()
        service.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)
    }

    private func startLiveDataWith(_ service: OBDService) {
        // Note: .fuelLevel excluded — library mock passes Double to %02X format specifier (crash).
        // .controlModuleVoltage excluded — no mock response implemented upstream.
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
                    if results.isEmpty { self.log("⚠️ Empty batch") }
                    var updated = self.liveData
                    for (cmd, measurement): (OBDCommand, MeasurementResult) in results {
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
}

// MARK: - Debug Stubs

#if DEBUG
extension OBDViewModel {
    static func stub(
        state: ConnectionState,
        info: OBDInfo? = nil,
        liveData: [String: String] = [:],
        error: String? = nil
    ) -> OBDViewModel {
        let vm = OBDViewModel(bindServiceState: false)
        vm.connectionState = state
        vm.obdInfo = info
        vm.liveData = liveData
        vm.errorMessage = error
        return vm
    }
}
#endif
