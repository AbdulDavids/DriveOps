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

    /// The poll list DriveOps shipped with before PIDs became selectable —
    /// used as the default selection so existing behavior doesn't change
    /// for anyone who hasn't opened the picker yet.
    static let defaultSelection: Set<OBDCommand> = [
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
        let restored = PIDCatalog.allLivePIDs.filter { savedSet.contains($0.properties.command) }
        // An empty save could mean "user deselected everything" or "nothing
        // was ever saved" — since polling with zero PIDs is never useful,
        // treat an empty result as "not yet configured" and fall back.
        return restored.isEmpty ? PIDCatalog.defaultSelection : Set(restored)
    }

    static func save(_ pids: Set<OBDCommand>) {
        UserDefaults.standard.set(pids.map(\.properties.command), forKey: key)
    }
}
