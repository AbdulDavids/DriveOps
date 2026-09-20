import Foundation
import Combine

/// Manual lap timing uses a monotonic clock, so clock/time-zone changes cannot
/// change a lap. Stopping discards the unfinished lap, preserving completed laps.
@MainActor
final class TrackSession: ObservableObject {
    /// The one lap-timing session, shared by the phone's Track view and the
    /// CarPlay scene so a lap started on the phone (or vice versa) is
    /// reflected on both — see `CarPlay/CarPlaySceneDelegate.swift`.
    static let shared = TrackSession()


    @Published private(set) var lapStartedAt: TimeInterval?
    @Published private(set) var laps: [TimeInterval] = []
    var isRunning: Bool { lapStartedAt != nil }
    var lastLap: TimeInterval? { laps.last }
    var bestLap: TimeInterval? { laps.min() }

    func start(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !isRunning else { return }
        lapStartedAt = time
    }
    func lap(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let start = lapStartedAt, time > start else { return }
        laps.append(time - start)
        lapStartedAt = time
    }
    func elapsed(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
        lapStartedAt.map { max(0, time - $0) }
    }
    func stop() { lapStartedAt = nil }
    func reset() { lapStartedAt = nil; laps = [] }

    static func formatted(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite, interval >= 0 else { return "—:——.——" }
        let hundredths = Int(interval * 100)
        return String(format: "%d:%02d.%02d", hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }
}
