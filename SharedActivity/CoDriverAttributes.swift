//
//  CoDriverAttributes.swift
//  DriveOps / CoDriverExtension
//
//  Shared between both targets (see project.pbxproj — this file has explicit
//  membership in both DriveOps and CoDriverExtension, since ActivityKit
//  requires the exact same ActivityAttributes type on the starting side
//  (the app, in OBDViewModel) and the rendering side (the widget extension).
//

import ActivityKit
import Foundation

// Explicitly nonisolated: this app target defaults to @MainActor isolation
// project-wide (SWIFT_DEFAULT_ACTOR_ISOLATION), but Activity<T>.update/.end
// are declared @concurrent in ActivityKit and can't accept an
// ActivityAttributes conformance pinned to the main actor.
nonisolated struct CoDriverAttributes: ActivityAttributes {
    /// One user-selected sensor's current reading, already formatted (e.g.
    /// "2450 rpm") — see Settings' Live Activity metrics picker and
    /// LiveActivityMetricsStore. Order matches the user's picked order.
    nonisolated struct MetricReading: Codable, Hashable {
        var label: String
        var formattedValue: String
    }

    nonisolated struct ContentState: Codable, Hashable {
        var metrics: [MetricReading]
        var isConnected: Bool
        var lapCount: Int
        var lastLapSeconds: Double?
        var bestLapSeconds: Double?
        var isLapRunning: Bool
    }

    /// Fixed for the lifetime of the activity.
    var startedAt: Date
}
