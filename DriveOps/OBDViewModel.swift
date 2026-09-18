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
    var activeService: OBDService?

    @Published var connectionState: ConnectionState = .disconnected
    @Published var obdInfo: OBDInfo?
    @Published var liveData: [String: String] = [:]
    @Published var metricHistory: [String: [MetricSample]] = [:]
    @Published var errorMessage: String?
    @Published var isConnecting = false
    @Published var activeConnectionType: ConnectionType?
    @Published var logs: [String] = []
    @Published var troubleCodes: [ECUID: [TroubleCode]] = [:]
    @Published var isScanningCodes = false
    @Published var scanError: String?

    private let historyLimit = 120
    private var cancellables = Set<AnyCancellable>()
    private var connectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let simulator = DrivingSimulator()

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
        startConnectingDemo()
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
        metricHistory = [:]
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
        metricHistory = [:]
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

    private func startConnectingDemo() {
        let service = OBDService(connectionType: .demo)
        isConnecting = true
        activeConnectionType = .demo
        errorMessage = nil
        log("Connecting via demo…")
        bind(service)
        connectTask = Task {
            do {
                let info = try await service.startConnection()
                guard !Task.isCancelled else { return }
                self.obdInfo = info
                self.isConnecting = false
                self.connectTask = nil
                self.log("Connected via demo (simulated driving cycle)")
                self.startSimulatedPoll()
            } catch {
                guard !Task.isCancelled else { return }
                self.log("demo connection failed: \(error.localizedDescription)")
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
                    let now = Date()
                    var updated = self.liveData
                    var updatedHistory = self.metricHistory
                    for (cmd, measurement): (OBDCommand, MeasurementResult) in results {
                        let key = cmd.properties.description
                        updated[key] = "\((measurement.value * 10).rounded() / 10) \(measurement.unit.symbol)"
                        let sample = MetricSample(timestamp: now, value: measurement.value)
                        var history = updatedHistory[key] ?? []
                        history.append(sample)
                        if history.count > self.historyLimit { history.removeFirst() }
                        updatedHistory[key] = history
                    }
                    self.liveData = updated
                    self.metricHistory = updatedHistory
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
    private func startSimulatedPoll() {
        log("Starting simulated poll…")
        pollTask = Task {
            while !Task.isCancelled {
                let readings = self.simulator.tick()
                let now = Date()
                var updated = self.liveData
                var updatedHistory = self.metricHistory
                for (key, reading) in readings {
                    updated[key] = "\((reading.value * 10).rounded() / 10) \(reading.unit)"
                    let sample = MetricSample(timestamp: now, value: reading.value)
                    var history = updatedHistory[key] ?? []
                    history.append(sample)
                    if history.count > self.historyLimit { history.removeFirst() }
                    updatedHistory[key] = history
                }
                self.liveData = updated
                self.metricHistory = updatedHistory
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
}

// MARK: - Preview Stubs

extension OBDViewModel {
    static func stub(
        state: ConnectionState,
        info: OBDInfo? = nil,
        liveData: [String: String] = [:],
        error: String? = nil,
        troubleCodes: [ECUID: [TroubleCode]] = [:],
        isScanningCodes: Bool = false,
        scanError: String? = nil
    ) -> OBDViewModel {
        let vm = OBDViewModel(bindServiceState: false)
        vm.connectionState = state
        vm.obdInfo = info
        vm.liveData = liveData
        vm.errorMessage = error
        vm.troubleCodes = troubleCodes
        vm.isScanningCodes = isScanningCodes
        vm.scanError = scanError
        return vm
    }
}
