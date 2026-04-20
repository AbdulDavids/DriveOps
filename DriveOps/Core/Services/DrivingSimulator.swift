//
//  DrivingSimulator.swift
//  DriveOps
//
//  Produces correlated, physically-plausible OBD values that follow a
//  repeating idle → accelerate → cruise → decelerate → idle cycle.
//

import Foundation

final class DrivingSimulator {

    // MARK: - Phase

    enum Phase: CaseIterable {
        case warmIdle, accelerate, cruise, decelerate
        var duration: TimeInterval {
            switch self {
            case .warmIdle:    return 8
            case .accelerate:  return 10
            case .cruise:      return 15
            case .decelerate:  return 7
            }
        }
    }

    // MARK: - State

    private var phase: Phase = .warmIdle
    private var phaseElapsed: TimeInterval = 0
    private var lastTick: Date = .now

    // Smoothed values
    private var rpm: Double = 750
    private var speed: Double = 0
    private var throttle: Double = 3
    private var coolant: Double = 65
    private var intakeTemp: Double = 25
    private var baro: Double = 101

    // MARK: - Tick

    /// Call every ~300 ms. Returns a dict of OBD description → (value, unit symbol).
    func tick() -> [String: (value: Double, unit: String)] {
        let now = Date.now
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now

        phaseElapsed += dt
        if phaseElapsed >= phase.duration {
            phaseElapsed = 0
            phase = nextPhase()
        }

        let t = phaseElapsed / phase.duration  // 0…1 within phase

        // Target values per phase
        let (targetRPM, targetSpeed, targetThrottle): (Double, Double, Double)
        switch phase {
        case .warmIdle:
            targetRPM = 750 + Double.random(in: -40...40)
            targetSpeed = 0
            targetThrottle = 3 + Double.random(in: -1...1)
        case .accelerate:
            targetRPM = 750 + t * 3250 + Double.random(in: -80...80)
            targetSpeed = t * 110 + Double.random(in: -2...2)
            targetThrottle = 15 + t * 65 + Double.random(in: -3...3)
        case .cruise:
            targetRPM = 2100 + Double.random(in: -120...120)
            targetSpeed = 100 + Double.random(in: -5...5)
            targetThrottle = 28 + Double.random(in: -3...3)
        case .decelerate:
            targetRPM = 2100 - t * 1350 + Double.random(in: -60...60)
            targetSpeed = 100 - t * 100 + Double.random(in: -2...2)
            targetThrottle = 28 - t * 25 + Double.random(in: -2...2)
        }

        rpm = lerp(rpm, targetRPM, factor: 0.18)
        speed = lerp(speed, targetSpeed, factor: 0.12).clamped(to: 0...220)
        throttle = lerp(throttle, targetThrottle, factor: 0.15).clamped(to: 0...100)

        // Coolant warms toward 90°C then stabilises
        let coolantTarget = phase == .warmIdle && coolant < 70 ? 72.0 : 88.0 + Double.random(in: -2...2)
        coolant = lerp(coolant, coolantTarget, factor: 0.005)

        // Intake temp tracks ambient + heat-soak
        let intakeTarget = 25 + (rpm / 4000) * 15 + Double.random(in: -1...1)
        intakeTemp = lerp(intakeTemp, intakeTarget, factor: 0.02)

        // MAF correlates with RPM and throttle
        let maf = (rpm / 6000) * (throttle / 100) * 250 + Double.random(in: -2...2)

        // Engine load correlates with throttle
        let load = (throttle * 0.85 + Double.random(in: -2...2)).clamped(to: 0...100)

        // Timing advance: more at cruise/low load
        let timingBase = phase == .cruise ? 18.0 : 12.0 - (throttle / 100) * 6
        let timing = (timingBase + Double.random(in: -1...1)).clamped(to: -10...40)

        // Intake manifold pressure: vacuum at idle, higher under load
        let intakePress = (30 + (throttle / 100) * 70 + Double.random(in: -2...2)).clamped(to: 20...100)

        baro = lerp(baro, 101.3 + Double.random(in: -0.2...0.2), factor: 0.01)

        return [
            "Engine RPM":              (rpm.clamped(to: 0...8000), "rpm"),
            "Vehicle Speed":           (speed, "km/h"),
            "Coolant Temperature":     (coolant, "°C"),
            "Throttle Position":       (throttle, "%"),
            "Engine Load":             (load, "%"),
            "Intake Air Temperature":  (intakeTemp, "°C"),
            "Mass Air Flow":           (maf.clamped(to: 0...655), "g/s"),
            "Barometric Pressure":     (baro, "kPa"),
            "Intake Manifold Pressure":(intakePress, "kPa"),
            "Timing Advance":          (timing, "°"),
        ]
    }

    // MARK: - Helpers

    private func nextPhase() -> Phase {
        switch phase {
        case .warmIdle:  return .accelerate
        case .accelerate: return .cruise
        case .cruise:    return .decelerate
        case .decelerate: return .warmIdle
        }
    }

    private func lerp(_ a: Double, _ b: Double, factor: Double) -> Double {
        a + (b - a) * factor
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
