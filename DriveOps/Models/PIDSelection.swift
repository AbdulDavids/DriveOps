//
//  PIDSelection.swift
//  DriveOps
//
//  The set of mode-1 PIDs the live-data poll requests, replacing what used
//  to be a fixed 10-PID list in OBDViewModel. See docs/architecture — every
//  vehicle supports a different subset of PIDs (a connected vehicle reports
//  its own list via OBDInfo.supportedPIDs, visible in the Vehicle card), so
//  a fixed list either polls PIDs a given car doesn't have or misses ones it
//  does. This lets the user choose from every live PID the library knows
//  about, independent of any single vehicle's supported set.
//

import Foundation
import SwiftOBD2

enum PIDCatalog {
    /// Every mode-1 PID the library exposes as a live sensor reading —
    /// excludes meta/bitmask PIDs like pidsA/pidsB/status/freezeDTC, which
    /// don't decode to a single MeasurementResult the way gauges expect.
    /// `CommandProperties.live` is exactly this distinction upstream.
    static let allLivePIDs: [OBDCommand] = OBDCommand.Mode1.allCases
        .map { OBDCommand.mode1($0) }
        .filter(\.properties.live)
        .sorted { $0.properties.command < $1.properties.command }

    /// A compact first dashboard. Existing saved choices are preserved; this
    /// only applies to first use or a new vehicle layout.
    static let defaultSelection: Set<OBDCommand> = [
        .mode1(.rpm),
        .mode1(.speed),
        .mode1(.coolantTemp),
        .mode1(.engineLoad),
    ]
}

/// Persists the user's PID selection across launches as their hex command
/// strings ("010C", …) — OBDCommand.Mode1 isn't RawRepresentable, so this is
/// the stable, human-readable identity to store rather than encoding the
/// enum itself.
enum PIDSelectionStore {
    private static let key = "selectedPIDCommands"

    static func load() -> Set<OBDCommand> {
        guard let saved = UserDefaults.standard.array(forKey: key) as? [String] else {
            return PIDCatalog.defaultSelection
        }
        let savedSet = Set(saved)
        // A stored empty array is an intentional empty dashboard. Only the
        // absence of this key means a first launch that needs essentials.
        return Set(PIDCatalog.allLivePIDs.filter { savedSet.contains($0.properties.command) })
    }

    static func save(_ pids: Set<OBDCommand>) {
        UserDefaults.standard.set(pids.map(\.properties.command), forKey: key)
    }
}

/// Ordered dashboard membership is distinct from the polling set. The order
/// is the user's layout; polling may temporarily include a sensor opened in a
/// detail view in a later iteration.
enum DashboardLayoutStore {
    private static let legacyKey = "dashboardMetricCommands"
    private static let key = "dashboardMetricCommandsByVehicle"

    static func load(for vehicleID: String) -> [String] {
        if let layouts = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]], let saved = layouts[vehicleID] {
            return saved
        }
        // Preserve the pre-redesign layout when a user first connects after
        // upgrading. It is copied to the chosen vehicle on its first save.
        if let legacy = UserDefaults.standard.stringArray(forKey: legacyKey) {
            return legacy
        }
        return PIDCatalog.defaultSelection.map(\.properties.command).sorted()
    }

    static func save(_ commands: [String], for vehicleID: String) {
        var layouts = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        layouts[vehicleID] = commands
        UserDefaults.standard.set(layouts, forKey: key)
    }
}

extension PIDCatalog {
    static func command(named command: String) -> OBDCommand? {
        allLivePIDs.first { $0.properties.command == command }
    }
}
