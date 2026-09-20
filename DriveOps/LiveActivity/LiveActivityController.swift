//
//  LiveActivityController.swift
//  DriveOps
//
//  Starts/updates/ends the CoDriver Live Activity (Dynamic Island + Lock
//  Screen) from the shared OBDViewModel/TrackSession state, the same
//  instances CarPlay's scene delegate observes — see
//  CarPlay/CarPlaySceneDelegate.swift for that sibling consumer. Kept
//  separate from OBDViewModel so the view model doesn't need to import
//  ActivityKit itself.
//

import ActivityKit
import Combine
import Foundation
import SwiftOBD2

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<CoDriverAttributes>?
    private var cancellables: Set<AnyCancellable> = []
    private var lastPushedAt: Date = .distantPast
    private let minPushInterval: TimeInterval = 1.5

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        let vm = OBDViewModel.shared
        vm.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleConnectionChange(state) }
            .store(in: &cancellables)
        vm.$liveMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushUpdate(throttled: true) }
            .store(in: &cancellables)
        TrackSession.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires just before the mutation lands, so
                // read the session on the next runloop turn.
                DispatchQueue.main.async { self?.pushUpdate(throttled: false) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTrackDemand()
                self?.pushUpdate(throttled: false)
            }
            .store(in: &cancellables)
    }

    private func handleConnectionChange(_ state: ConnectionState) {
        if state.isConnected {
            updateTrackDemand()
            beginIfNeeded()
        } else {
            OBDViewModel.shared.setTrackDemand([], source: "liveActivity")
            end()
        }
    }

    /// Re-asserted whenever the picked metrics change (Settings write) or a
    /// new activity starts — not every content refresh, since setTrackDemand
    /// isn't cheap to call every poll tick and the selection rarely changes.
    private func updateTrackDemand() {
        OBDViewModel.shared.setTrackDemand(Set(LiveActivityMetricsStore.load()), source: "liveActivity")
    }

    private func beginIfNeeded() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = CoDriverAttributes(startedAt: Date())
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState(), staleDate: nil)
            )
        } catch {
            OBDViewModel.shared.log("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    private func pushUpdate(throttled: Bool) {
        guard let activity else { return }
        if throttled {
            let now = Date()
            guard now.timeIntervalSince(lastPushedAt) >= minPushInterval else { return }
            lastPushedAt = now
        }
        let content = ActivityContent(state: contentState(), staleDate: nil)
        Task { await activity.update(content) }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func contentState() -> CoDriverAttributes.ContentState {
        let vm = OBDViewModel.shared
        let session = TrackSession.shared
        return CoDriverAttributes.ContentState(
            metrics: selectedMetricReadings(vm: vm),
            isConnected: vm.connectionState.isConnected,
            lapCount: session.laps.count,
            lastLapSeconds: session.lastLap,
            bestLapSeconds: session.bestLap,
            isLapRunning: session.isRunning
        )
    }

    private func selectedMetricReadings(vm: OBDViewModel) -> [CoDriverAttributes.MetricReading] {
        LiveActivityMetricsStore.load().map { id in
            let label = Self.shortLabel(for: id)
            let value = reading(id, vm: vm).map(Self.compactFormat) ?? "—"
            return CoDriverAttributes.MetricReading(label: label, formattedValue: value)
        }
    }

    /// Short enough to never truncate in a 3-up row on the Lock Screen or
    /// Dynamic Island (the full sensor name, e.g. "Intake Manifold
    /// Pressure", clips badly at that width) — a small fixed table for the
    /// PIDs users are actually likely to pick here, falling back to the
    /// full name (still uppercased/truncated by the view) for anything else.
    private static func shortLabel(for command: String) -> String {
        let table: [String: String] = [
            "010C": "RPM", "010D": "SPEED", "0105": "COOLANT", "0104": "LOAD",
            "0111": "THROTTLE", "010F": "INTAKE T", "0110": "MAF",
            "010B": "MANIFOLD", "0133": "BARO", "010E": "TIMING",
        ]
        if let short = table[command] { return short }
        guard let pid = PIDCatalog.command(named: command) else { return command }
        return MetricCatalog.displayName(for: pid).uppercased()
    }

    /// MetricCatalog.format uses NumberFormatter(.decimal), which adds a
    /// thousands separator ("1,100 rpm") — fine in the full app UI, but too
    /// wide for a wristwatch-sized Live Activity column. This drops the
    /// separator and keeps the unit only when it's short.
    private static func compactFormat(_ metric: LiveMetric) -> String {
        guard let value = metric.value else { return "—" }
        let rounded = value.rounded()
        let number = abs(rounded) >= 1000 ? String(format: "%.0f", rounded) : "\(Int(rounded))"
        guard !metric.unit.isEmpty, metric.unit.count <= 4 else { return number }
        return "\(number) \(metric.unit)"
    }

    private func reading(_ id: String, vm: OBDViewModel) -> LiveMetric? {
        guard let metric = vm.liveMetrics[id], metric.isUsable,
              Date().timeIntervalSince(metric.updatedAt) <= 5 else { return nil }
        return metric
    }
}
