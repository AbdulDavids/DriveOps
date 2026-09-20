//
//  CarPlaySceneDelegate.swift
//  DriveOps
//
//  CarPlay's screen only ever shows one of Apple's fixed templates — there is
//  no custom-canvas rendering under the Parking entitlement this targets, so
//  this is a from-scratch, list-based read of the same live data the phone's
//  Track view shows (see TrackView.swift), not a port of its custom
//  rev-strip UI. CPInformationTemplate is used over CPGridTemplate because
//  its `items` can be updated in place each refresh tick — CPGridTemplate's
//  title/buttons are init-only and would require replacing the whole root
//  template every second. Requires the com.apple.developer.carplay-parking
//  entitlement to be granted by Apple before it will connect to a real head
//  unit; runs fine in the CarPlay Simulator without it.
//

import CarPlay
import Combine
import SwiftOBD2
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var informationTemplate: CPInformationTemplate?
    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let slots = ["010D", "010C", "0105", "0111"]

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let template = makeInformationTemplate()
        informationTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        // Demand these PIDs directly: CarPlay can be the only active scene
        // (phone locked/backgrounded), so it can't rely on the phone's Track
        // view having already called setTrackDemand. Keyed separately from
        // Track's own demand so either scene closing doesn't clear the
        // other's PIDs.
        OBDViewModel.shared.setTrackDemand(Set(slots), source: "carplay")

        observeSessionChanges()
        startRefreshTimer()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
        self.interfaceController = nil
        informationTemplate = nil
        OBDViewModel.shared.setTrackDemand([], source: "carplay")
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func observeSessionChanges() {
        TrackSession.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        // Live metrics still get a coalesced refresh via the 1s timer above
        // (they change every poll cycle); this catches connect/disconnect
        // transitions immediately instead of waiting up to a second.
        OBDViewModel.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        guard let informationTemplate else { return }
        informationTemplate.title = title()
        informationTemplate.items = infoItems()
        informationTemplate.actions = actions()
    }

    // MARK: - Content

    private func makeInformationTemplate() -> CPInformationTemplate {
        CPInformationTemplate(
            title: title(),
            layout: .twoColumn,
            items: infoItems(),
            actions: actions()
        )
    }

    private func title() -> String {
        let session = TrackSession.shared
        if session.isRunning {
            return "LAP \(session.laps.count + 1) · \(TrackSession.formatted(session.elapsed()))"
        }
        return session.laps.isEmpty ? "DriveOps Track" : "Best \(TrackSession.formatted(session.bestLap))"
    }

    private func infoItems() -> [CPInformationItem] {
        let vm = OBDViewModel.shared
        let sensorItems = slots.map { id -> CPInformationItem in
            let metric = reading(id, vm: vm)
            let name = PIDCatalog.command(named: id).map { MetricCatalog.displayName(for: $0) } ?? id
            let value = metric.map { MetricCatalog.format($0) } ?? "—"
            return CPInformationItem(title: name, detail: value)
        }
        let session = TrackSession.shared
        let lapRows = [
            CPInformationItem(title: "Last Lap", detail: TrackSession.formatted(session.lastLap)),
            CPInformationItem(title: "Best Lap", detail: TrackSession.formatted(session.bestLap)),
        ]
        return sensorItems + lapRows
    }

    private func actions() -> [CPTextButton] {
        let session = TrackSession.shared
        if session.isRunning {
            return [
                CPTextButton(title: "Lap", textStyle: .confirm) { _ in session.lap() },
                CPTextButton(title: "Stop", textStyle: .normal) { _ in session.stop() },
            ]
        }
        return [
            CPTextButton(title: "Start", textStyle: .confirm) { _ in session.start() },
        ]
    }

    private func reading(_ id: String, vm: OBDViewModel) -> LiveMetric? {
        guard vm.connectionState.isConnected, let metric = vm.liveMetrics[id], metric.isUsable,
              Date().timeIntervalSince(metric.updatedAt) <= 2 else { return nil }
        return metric
    }
}
