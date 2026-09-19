//
//  OBDViewModel.swift
//  DriveOps
//

import Foundation
import Combine
import SwiftOBD2
import VIN
import os

/// The connection the UI is showing, layered over the library's `ConnectionType`
/// (`.bluetooth` / `.wifi`) to add `.demo`, which never touches `OBDService` —
/// demo mode runs entirely on the local `DrivingSimulator`.
enum AppConnectionType: String {
    case bluetooth = "Bluetooth"
    case wifi = "Wi-Fi"
    case demo = "Demo"
}

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
    @Published var activeConnectionType: AppConnectionType?
    @Published var logs: [String] = []
    @Published var troubleCodes: [ECUID: [TroubleCode]] = [:]
    @Published var isScanningCodes = false
    @Published var scanError: String?

    /// The connected vehicle's VIN, decoded into structured identity info
    /// (manufacturer, model year, region, …) when the adapter reported one.
    var decodedVIN: VIN? {
        guard let raw = obdInfo?.vin, VIN.isValid(raw) else { return nil }
        return VIN(content: raw)
    }

    private let historyLimit = 120
    private let logLimit = 500
    private var cancellables = Set<AnyCancellable>()
    private var connectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let simulator = DrivingSimulator()
    private var pollCycleCount = 0
    private var pollErrorCount = 0

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
        if logs.count > logLimit {
            logs.removeFirst(logs.count - logLimit)
        }
        AppLogger.connection.debug("\(message, privacy: .public)")
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
        log("Connection cancelled by user (was connecting via \(activeConnectionType?.rawValue ?? "unknown")).")
        AppLogger.connection.notice("cancelConnection type=\(self.activeConnectionType?.rawValue ?? "unknown", privacy: .public)")
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
        log("Disconnecting… (\(pollCycleCount) poll cycles, \(pollErrorCount) errors this session)")
        AppLogger.connection.notice("disconnect pollCycles=\(self.pollCycleCount) pollErrors=\(self.pollErrorCount)")
        pollTask?.cancel()
        pollTask = nil
        activeService?.stopConnection()
        activeService = nil
        connectionState = .disconnected
        activeConnectionType = nil
        obdInfo = nil
        liveData = [:]
        metricHistory = [:]
        pollCycleCount = 0
        pollErrorCount = 0
    }

    private func startConnecting(type: AppConnectionType, service: OBDService) {
        isConnecting = true
        activeConnectionType = type
        errorMessage = nil
        let startedAt = Date()
        log("Connecting via \(type.rawValue)…")
        AppLogger.connection.info("startConnection begin type=\(type.rawValue, privacy: .public)")
        bind(service)
        connectTask = Task {
            do {
                let info = try await service.startConnection()
                guard !Task.isCancelled else {
                    self.log("\(type.rawValue) connect task cancelled after connection succeeded; disconnecting.")
                    service.stopConnection()
                    return
                }
                let elapsed = Date().timeIntervalSince(startedAt)
                self.obdInfo = info
                self.isConnecting = false
                self.connectTask = nil
                self.log("Connected via \(type.rawValue) in \(String(format: "%.2f", elapsed))s. Protocol: \(info.obdProtocol?.description ?? "unknown"), VIN: \(info.vin ?? "n/a"), PIDs: \(info.supportedPIDs?.count ?? 0), ECUs: \(info.ecuMap?.count ?? 0)")
                AppLogger.connection.info("startConnection success type=\(type.rawValue, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2))s protocol=\(info.obdProtocol?.description ?? "unknown", privacy: .public)")
                self.startLiveDataWith(service)
            } catch {
                guard !Task.isCancelled else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                self.log("\(type.rawValue) connection failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
                AppLogger.connection.error("startConnection failed type=\(type.rawValue, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2))s error=\(String(describing: error), privacy: .public)")
                self.errorMessage = error.localizedDescription
                self.isConnecting = false
                self.activeConnectionType = nil
                self.connectTask = nil
            }
        }
    }

    // Demo mode never touches OBDService — it runs the local DrivingSimulator directly,
    // since the library only ships mock data behind #if targetEnvironment(simulator),
    // with no runtime-selectable demo connection type to request it on a real device.
    private func startConnectingDemo() {
        isConnecting = true
        activeConnectionType = .demo
        errorMessage = nil
        log("Connecting via demo…")
        AppLogger.demo.info("startConnectingDemo begin")
        connectTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else {
                self.log("Demo connect cancelled before completion.")
                return
            }
            self.isConnecting = false
            self.connectTask = nil
            self.connectionState = .connectedToVehicle
            self.log("Connected via demo (simulated driving cycle)")
            AppLogger.demo.info("startConnectingDemo connected")
            self.startSimulatedPoll()
        }
    }

    // MARK: - Private

    private func bind(_ service: OBDService) {
        activeService = service
        cancellables.removeAll()
        service.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)

        // Surface the library's own internal logging (BLE/WiFi transport detail,
        // handshake retries, ELM327 command tracing) in the app's Logs tab, not
        // just Console.app — this is the detail that actually matters once we're
        // debugging a real adapter instead of the simulator's mock transport.
        service.onLog = { [weak self] message in
            self?.log("[lib] \(message)")
        }
        service.onAdapterInfoUpdated = { [weak self] info in
            guard !info.isEmpty else { return }
            self?.log("Adapter info: \(info.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))")
        }
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

        log("Starting live data poll for \(pids.count) PIDs: \(pids.map(\.properties.description).joined(separator: ", "))")
        pollCycleCount = 0
        pollErrorCount = 0
        pollTask = Task {
            while !Task.isCancelled {
                let cycleStart = Date()
                do {
                    let results = try await service.requestPIDs(pids, unit: .metric)
                    self.pollCycleCount += 1
                    let elapsedMs = Date().timeIntervalSince(cycleStart) * 1000

                    if results.isEmpty {
                        self.log("⚠️ Empty batch (cycle #\(self.pollCycleCount), \(String(format: "%.0f", elapsedMs))ms)")
                    } else if results.count < pids.count {
                        let missing = Set(pids).subtracting(results.keys).map(\.properties.description)
                        self.log("⚠️ Partial batch: \(results.count)/\(pids.count) PIDs (missing: \(missing.joined(separator: ", ")))")
                    }

                    // Full detail goes to the system log every cycle; the in-app
                    // Logs tab only gets a periodic summary so a long drive doesn't
                    // flood it with one line per 300ms tick.
                    AppLogger.liveData.debug("poll cycle #\(self.pollCycleCount) results=\(results.count)/\(pids.count) elapsed=\(elapsedMs, format: .fixed(precision: 0))ms")
                    if self.pollCycleCount % 50 == 0 {
                        self.log("Live data: \(self.pollCycleCount) cycles polled, \(self.pollErrorCount) errors, last cycle \(String(format: "%.0f", elapsedMs))ms")
                    }

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
                    self.pollErrorCount += 1
                    if !Task.isCancelled {
                        self.log("Poll error (cycle #\(self.pollCycleCount), \(self.pollErrorCount) total errors): \(error.localizedDescription)")
                        AppLogger.liveData.error("poll error cycle=\(self.pollCycleCount) totalErrors=\(self.pollErrorCount) error=\(String(describing: error), privacy: .public)")
                        self.errorMessage = error.localizedDescription
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            self.log("Live data poll stopped after \(self.pollCycleCount) cycle(s), \(self.pollErrorCount) error(s).")
        }
    }
    private func startSimulatedPoll() {
        log("Starting simulated poll…")
        pollCycleCount = 0
        pollTask = Task {
            while !Task.isCancelled {
                let readings = self.simulator.tick()
                self.pollCycleCount += 1
                if self.pollCycleCount % 50 == 0 {
                    AppLogger.demo.debug("simulated poll cycle #\(self.pollCycleCount), phase readings=\(readings.count)")
                }
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
