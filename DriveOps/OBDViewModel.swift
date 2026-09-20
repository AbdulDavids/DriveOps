//
//  OBDViewModel.swift
//  DriveOps
//

import Foundation
import Combine
import CoreBluetooth
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
    /// The one live connection/data instance, shared by the phone UI scene and
    /// the CarPlay scene so CarPlay reflects the same connection instead of
    /// opening a second, disconnected `OBDService`.
    static let shared = OBDViewModel()

    private let bluetoothService = OBDService(connectionType: .bluetooth)
    var activeService: OBDService?

    @Published var connectionState: ConnectionState = .disconnected
    @Published var obdInfo: OBDInfo?
    @Published var liveData: [String: String] = [:]
    @Published var metricHistory: [String: [MetricSample]] = [:]
    /// Typed, validated readings for the dashboard. `liveData` remains during
    /// the migration for older views and previews; new UI must use this store.
    @Published private(set) var liveMetrics: [String: LiveMetric] = [:]
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

    /// A short "you're asking about a 2019 Honda vehicle" style fragment built
    /// from `decodedVIN`, for injection into AI Mechanic prompts/summaries so
    /// explanations are vehicle-aware instead of generic. Returns `nil` (never
    /// a placeholder like "unknown vehicle") when there's no VIN or nothing
    /// decoded from it, so callers can `if let` this in without ever forcing
    /// broken or misleading context into a prompt.
    var vehicleContextForPrompt: String? {
        guard let decodedVIN else { return nil }

        // Build "2019 Honda" style fragment from whichever of year/manufacturer
        // actually decoded — VIN decoding is best-effort per-field, so either
        // one (or both) can be missing even for a syntactically valid VIN.
        let yearAndMake = [
            decodedVIN.modelYear.map { "\($0)" },
            decodedVIN.manufacturer,
        ].compactMap { $0 }.joined(separator: " ")

        guard !yearAndMake.isEmpty else { return nil }

        var context = "a \(yearAndMake) vehicle"
        if let country = decodedVIN.countryName {
            context += " (built in \(country))"
        }
        return context
    }

    /// BLE peripherals seen since the last `startPeripheralScan()`. Backs the
    /// device picker sheet — see `docs/architecture/connection-lifecycle.md`.
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var isScanningForPeripherals = false

    /// The PIDs the live-data poll requests each cycle — user-selectable via
    /// the PID picker in Settings, replacing the old fixed 10-PID list. See
    /// `Models/PIDSelection.swift`. Persisted immediately on every change so
    /// a picker edit takes effect on the very next poll cycle without
    /// needing a reconnect.
    @Published var selectedPIDs: Set<OBDCommand> = PIDSelectionStore.load() {
        didSet {
            guard selectedPIDs != oldValue else { return }
            PIDSelectionStore.save(selectedPIDs)
            log("PID selection changed: \(selectedPIDs.count) PID(s) selected.")
        }
    }

    // Track (phone) and CarPlay are independent temporary subscribers, keyed
    // separately so one closing (e.g. the phone's Track view disappearing)
    // doesn't clear the PIDs the other still needs. Neither alters the
    // user's persisted dashboard/poll selection.
    private var trackDemands: [String: Set<OBDCommand>] = [:]
    func setTrackDemand(_ ids: Set<String>, source: String = "track") {
        trackDemands[source] = Set(ids.compactMap { PIDCatalog.command(named: $0) })
    }
    var requestedPIDs: Set<OBDCommand> {
        trackDemands.values.reduce(selectedPIDs) { $0.union($1) }
    }

    @Published private(set) var dashboardVehicleID = "default"
    @Published var dashboardMetricIDs: [String] = DashboardLayoutStore.load(for: "default") {
        didSet {
            guard dashboardMetricIDs != oldValue else { return }
            DashboardLayoutStore.save(dashboardMetricIDs, for: dashboardVehicleID)
        }
    }

    private func activateDashboard(for vehicleID: String) {
        dashboardVehicleID = vehicleID
        dashboardMetricIDs = DashboardLayoutStore.load(for: vehicleID)
        selectedPIDs = Set(dashboardMetricIDs.compactMap(PIDCatalog.command(named:)))
        liveData = [:]
        metricHistory = [:]
        liveMetrics = [:]
    }

    func addToDashboard(_ pid: OBDCommand) {
        if !dashboardMetricIDs.contains(pid.properties.command) {
            dashboardMetricIDs.append(pid.properties.command)
        }
        selectedPIDs.insert(pid)
    }

    func removeFromDashboard(_ command: String) {
        dashboardMetricIDs.removeAll { $0 == command }
        if let pid = PIDCatalog.command(named: command) {
            selectedPIDs.remove(pid)
        }
        liveData = liveData.filter { key, _ in
            dashboardMetricIDs.contains { PIDCatalog.command(named: $0).map { MetricCatalog.displayName(for: $0) == key } ?? false }
        }
    }

    func moveDashboardMetric(from source: IndexSet, to destination: Int) {
        let moving = source.map { dashboardMetricIDs[$0] }
        for index in source.sorted(by: >) {
            dashboardMetricIDs.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        dashboardMetricIDs.insert(contentsOf: moving, at: adjustedDestination)
    }

    private let historyLimit = 120
    private let logLimit = 500
    private var cancellables = Set<AnyCancellable>()
    private var connectTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let simulator = DrivingSimulator()
    private var pollCycleCount = 0
    private var pollErrorCount = 0
    /// Consecutive (not lifetime) poll failures — reset on any successful
    /// cycle. A handful of transient BLE hiccups in a row (a dropped write,
    /// a momentary link glitch) shouldn't need a full reconnect, but a truly
    /// dead connection shouldn't spin forever either.
    private var consecutivePollErrorCount = 0
    private static let maxConsecutivePollErrors = 5

    init(bindServiceState: Bool = true) {
        if bindServiceState {
            bluetoothService.$connectionState
                .receive(on: DispatchQueue.main)
                .assign(to: &$connectionState)
        }
        bluetoothService.onPeripheralsUpdated = { [weak self] peripherals in
            self?.discoveredPeripherals = peripherals
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

    // MARK: - Peripheral discovery

    /// Starts (or restarts) an unfiltered BLE scan so the device picker can
    /// show every nearby peripheral, not just ones the library already
    /// recognises by service UUID — see `docs/architecture/connection-lifecycle.md`.
    func startPeripheralScan() {
        scanTask?.cancel()
        discoveredPeripherals = []
        isScanningForPeripherals = true
        log("Scanning for BLE devices…")
        AppLogger.connection.info("startPeripheralScan begin")
        scanTask = Task {
            do {
                try await bluetoothService.scanForPeripherals()
            } catch {
                guard !Task.isCancelled else { return }
                self.log("Peripheral scan failed: \(error.localizedDescription)")
                AppLogger.connection.error("startPeripheralScan failed error=\(String(describing: error), privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            self.isScanningForPeripherals = false
            self.log("Scan finished — \(self.discoveredPeripherals.count) device(s) found.")
        }
    }

    func stopPeripheralScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanningForPeripherals = false
    }

    // MARK: - Connection

    /// Connects to whichever BLE peripheral the device picker scan finds
    /// first. Kept for demo/preview convenience — the picker itself should
    /// call `connect(to:)` with the user's actual choice.
    func connect() {
        startConnecting(type: .bluetooth, service: bluetoothService)
    }

    /// Connects to a specific peripheral the user picked, bypassing the
    /// scan-and-take-first behavior `connect()` falls back to. This is what
    /// makes an adapter other than "whichever one answers first" usable when
    /// more than one BLE OBD2 device is in range.
    func connect(to peripheral: CBPeripheral) {
        stopPeripheralScan()
        startConnecting(type: .bluetooth, service: bluetoothService, peripheral: peripheral)
    }

    func connectWifi() {
        startConnecting(type: .wifi, service: OBDService(connectionType: .wifi))
    }

    /// Tries to reconnect to the last Bluetooth adapter that connected
    /// successfully, without the user having to open the device picker again.
    /// Silent no-op when there's nothing saved, the device isn't currently
    /// retrievable (out of range, powered off, forgotten by iOS), or a
    /// connection attempt is already underway — this only ever runs once, on
    /// launch, before the user has done anything else.
    func autoConnectIfPossible() {
        guard !isConnecting, connectionState == .disconnected, let identifier = LastKnownDeviceStore.load() else { return }
        Task {
            guard let peripheral = await self.bluetoothService.retrievePeripheral(identifier: identifier) else {
                self.log("Auto-connect: last known device is no longer available.")
                return
            }
            guard !self.isConnecting, self.connectionState == .disconnected else { return }
            self.log("Auto-connecting to last known device…")
            self.connect(to: peripheral)
        }
    }

    func connectDemo() {
        startConnectingDemo()
    }

    func cancelConnection() {
        log("Connection cancelled by user (was connecting via \(activeConnectionType?.rawValue ?? "unknown")).")
        AppLogger.connection.notice("cancelConnection type=\(self.activeConnectionType?.rawValue ?? "unknown", privacy: .public)")
        stopPeripheralScan()
        connectTask?.cancel()
        connectTask = nil
        activeService?.stopConnection()
        activeService = nil
        isConnecting = false
        activeConnectionType = nil
        connectionState = .disconnected
        metricHistory = [:]
        liveMetrics = [:]
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
        liveMetrics = [:]
        pollCycleCount = 0
        pollErrorCount = 0
    }

    private func startConnecting(type: AppConnectionType, service: OBDService, peripheral: CBPeripheral? = nil) {
        isConnecting = true
        activeConnectionType = type
        errorMessage = nil
        let startedAt = Date()
        log("Connecting via \(type.rawValue)\(peripheral.map { " to \($0.name ?? $0.identifier.uuidString)" } ?? "")…")
        AppLogger.connection.info("startConnection begin type=\(type.rawValue, privacy: .public) peripheral=\(peripheral?.identifier.uuidString ?? "auto", privacy: .public)")
        bind(service)
        connectTask = Task {
            do {
                let info = try await service.startConnection(peripheral: peripheral)
                guard !Task.isCancelled else {
                    self.log("\(type.rawValue) connect task cancelled after connection succeeded; disconnecting.")
                    service.stopConnection()
                    return
                }
                let elapsed = Date().timeIntervalSince(startedAt)
                self.obdInfo = info
                self.activateDashboard(for: info.vin?.uppercased() ?? "unidentified")
                self.isConnecting = false
                self.connectTask = nil
                if type == .bluetooth, let identifier = peripheral?.identifier ?? service.connectedPeripheral?.identifier {
                    LastKnownDeviceStore.save(identifier)
                }
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
            self.obdInfo = Self.demoOBDInfo
            self.activateDashboard(for: "demo")
            self.log("Connected via demo (simulated driving cycle)")
            AppLogger.demo.info("startConnectingDemo connected")
            self.startSimulatedPoll()
        }
    }

    /// A plausible, checksum-valid VIN (1HG = Honda, position 10 "M" = 2021)
    /// so Diagnostics' vehicle card and the AI Mechanic's vehicle-aware
    /// prompt (see vehicleContextForPrompt) have something realistic to show
    /// in demo mode, matching what a real adapter would report.
    ///
    /// OBDInfo has no public initializer (its implicit memberwise init is
    /// internal to SwiftOBD2), so it's decoded from JSON — same workaround
    /// ContentView's preview data already uses — then the remaining fields
    /// are set directly since they're `public var`.
    private static let demoOBDInfo: OBDInfo? = {
        guard var info = try? JSONDecoder().decode(OBDInfo.self, from: Data(#"{"vin":"1HGBH41JXMN109186"}"#.utf8)) else {
            return nil
        }
        info.supportedPIDs = PIDCatalog.allLivePIDs
        info.obdProtocol = .protocol6
        info.ecuMap = [0x00: .engine, 0x01: .transmission]
        return info
    }()

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
        log("Starting live data poll for \(selectedPIDs.count) PID(s): \(selectedPIDs.map(\.properties.description).sorted().joined(separator: ", "))")
        pollCycleCount = 0
        pollErrorCount = 0
        consecutivePollErrorCount = 0
        pollTask = Task {
            while !Task.isCancelled {
                // Read fresh each cycle (not captured once at loop start) so a
                // picker edit mid-session takes effect on the very next tick
                // without needing a reconnect — see selectedPIDs' didSet.
                let pids = self.requestedPIDs.sorted { $0.properties.command < $1.properties.command }
                guard !pids.isEmpty else {
                    // Only reachable transiently while the picker UI is mid-edit
                    // (PIDSelectionStore never persists an empty set as the
                    // resting selection) — skip the cycle rather than issuing a
                    // pointless zero-PID request or treating it as an error.
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }
                let cycleStart = Date()
                do {
                    let results = try await service.requestPIDs(pids, unit: .metric)
                    self.pollCycleCount += 1
                    self.consecutivePollErrorCount = 0
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
                    var updatedMetrics = self.liveMetrics
                    let returnedCommands = Set(results.keys.map(\.properties.command))
                    for command in self.requestedPIDs.map(\.properties.command) where !returnedCommands.contains(command) {
                        guard let prior = updatedMetrics[command], now.timeIntervalSince(prior.updatedAt) > 2 else { continue }
                        updatedMetrics[command] = prior.markedStale()
                    }
                    let batchPIDs = Set(pids.map(\.properties.command))
                    for (cmd, measurement): (OBDCommand, MeasurementResult) in results {
                        let metric = MetricCatalog.reading(for: cmd, result: measurement, at: now, batchPIDs: batchPIDs)
                        let key = metric.name
                        updatedMetrics[metric.id] = metric
                        guard let value = metric.value else { continue }
                        updated[key] = MetricCatalog.format(metric)
                        let sample = MetricSample(timestamp: now, value: value)
                        var history = updatedHistory[key] ?? []
                        history.append(sample)
                        if history.count > self.historyLimit { history.removeFirst() }
                        updatedHistory[key] = history
                    }
                    self.liveData = updated
                    self.metricHistory = updatedHistory
                    self.liveMetrics = updatedMetrics
                } catch {
                    self.pollErrorCount += 1
                    self.consecutivePollErrorCount += 1
                    guard !Task.isCancelled else { break }
                    self.log("Poll error (cycle #\(self.pollCycleCount), \(self.pollErrorCount) total errors, \(self.consecutivePollErrorCount) consecutive): \(error.localizedDescription)")
                    AppLogger.liveData.error("poll error cycle=\(self.pollCycleCount) totalErrors=\(self.pollErrorCount) consecutive=\(self.consecutivePollErrorCount) error=\(String(describing: error), privacy: .public)")
                    self.errorMessage = error.localizedDescription
                    // A handful of consecutive failures in a row means the
                    // connection itself is gone (not a single dropped PID —
                    // that no longer throws here at all, see requestPIDs'
                    // NO DATA handling), so stop rather than spin forever
                    // against a dead link. Anything short of that is worth
                    // riding out: a transient BLE write/notify hiccup
                    // shouldn't cost the whole session and force a
                    // reconnect.
                    guard self.consecutivePollErrorCount < Self.maxConsecutivePollErrors else {
                        self.log("Stopping live data poll after \(self.consecutivePollErrorCount) consecutive errors.")
                        break
                    }
                }
                // Backgrounded: space cycles out to stretch the limited
                // beginBackgroundTask time budget further — see
                // BackgroundPollController. Foreground keeps the normal
                // near-continuous cadence.
                let delay = BackgroundPollController.shared.isBackgrounded
                    ? BackgroundPollController.backgroundPollInterval
                    : 0.3
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
                var updatedMetrics = self.liveMetrics
                for (key, reading) in readings {
                    let metric = MetricCatalog.simulated(name: key, value: reading.value, unit: reading.unit, at: now)
                    guard self.requestedPIDs.contains(where: { $0.properties.command == metric.id }) else { continue }
                    updatedMetrics[metric.id] = metric
                    updated[metric.name] = MetricCatalog.format(metric)
                    let sample = MetricSample(timestamp: now, value: reading.value)
                    var history = updatedHistory[metric.name] ?? []
                    history.append(sample)
                    if history.count > self.historyLimit { history.removeFirst() }
                    updatedHistory[metric.name] = history
                }
                self.liveData = updated
                self.metricHistory = updatedHistory
                self.liveMetrics = updatedMetrics
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
        vm.liveMetrics = liveData.reduce(into: [:]) { metrics, item in
            let parts = item.value.split(separator: " ", maxSplits: 1).map(String.init)
            let value = Double(parts.first ?? "") ?? 0
            let unit = parts.count > 1 ? parts[1] : ""
            let metric = MetricCatalog.simulated(name: item.key, value: value, unit: unit)
            metrics[metric.id] = metric
        }
        vm.errorMessage = error
        vm.troubleCodes = troubleCodes
        vm.isScanningCodes = isScanningCodes
        vm.scanError = scanError
        return vm
    }
}
