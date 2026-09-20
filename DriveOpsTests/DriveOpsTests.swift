//
//  DriveOpsTests.swift
//  DriveOpsTests
//

import XCTest
@testable import DriveOps

@MainActor
final class DriveOpsTests: XCTestCase {
    func testManualLapsAndRestart() {
        let session = TrackSession()
        session.lap(at: 10)
        XCTAssertTrue(session.laps.isEmpty)
        session.start(at: 100)
        session.start(at: 110)
        session.lap(at: 181.25)
        session.lap(at: 260)
        XCTAssertEqual(session.laps, [81.25, 78.75])
        XCTAssertEqual(session.lastLap, 78.75)
        XCTAssertEqual(session.bestLap, 78.75)
        XCTAssertEqual(session.elapsed(at: 270), 10)
        session.stop()
        XCTAssertNil(session.elapsed(at: 280))
        session.start(at: 300)
        session.lap(at: 360)
        XCTAssertEqual(session.lastLap, 60)
        XCTAssertEqual(TrackSession.formatted(81.25), "1:21.25")
        session.reset()
        XCTAssertTrue(session.laps.isEmpty)
        XCTAssertFalse(session.isRunning)
    }

    func testRPMRecoveryStripsOnlyTheKnownPIDEcho() {
        let recovered = MetricCatalog.normaliseRPMValue(197_681)

        XCTAssertTrue(recovered.recovered)
        XCTAssertEqual(recovered.value, 1_073)

        let ordinary = MetricCatalog.normaliseRPMValue(2_750)
        XCTAssertFalse(ordinary.recovered)
        XCTAssertEqual(ordinary.value, 2_750)
    }

    func testRPMRecoveryHandlesEchoFromAnyBatchedPID() {
        // Same corrupted payload as the 0x0C case above, but with 010D's PID
        // byte (0x0D) leaked in as the top byte instead of RPM's own — the
        // shape Track hits once its extra PIDs join the poll batch.
        let recoveredFromOtherPID = MetricCatalog.normaliseRPMValue(214_065, knownPIDBytes: [0x0C, 0x0D])
        XCTAssertTrue(recoveredFromOtherPID.recovered)
        XCTAssertEqual(recoveredFromOtherPID.value, 1_073)

        // Same value is left alone when that PID isn't actually in the batch.
        let notInBatch = MetricCatalog.normaliseRPMValue(214_065, knownPIDBytes: [0x0C])
        XCTAssertFalse(notInBatch.recovered)
        XCTAssertEqual(notInBatch.value, 214_065)
    }

    func testStaleMetricKeepsItsLastValue() {
        let metric = LiveMetric(
            id: "010C", name: "Engine RPM", category: "Engine", value: 1_073,
            unit: "rpm", updatedAt: .now, quality: .live
        )

        let stale = metric.markedStale()
        XCTAssertEqual(stale.value, 1_073)
        XCTAssertEqual(stale.quality, .stale)
    }
}
