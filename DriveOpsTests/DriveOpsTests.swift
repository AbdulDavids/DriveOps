//
//  DriveOpsTests.swift
//  DriveOpsTests
//

import XCTest
@testable import DriveOps

@MainActor
final class DriveOpsTests: XCTestCase {
    func testRPMRecoveryStripsOnlyTheKnownPIDEcho() {
        let recovered = MetricCatalog.normaliseRPMValue(197_681)

        XCTAssertTrue(recovered.recovered)
        XCTAssertEqual(recovered.value, 1_073)

        let ordinary = MetricCatalog.normaliseRPMValue(2_750)
        XCTAssertFalse(ordinary.recovered)
        XCTAssertEqual(ordinary.value, 2_750)
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
