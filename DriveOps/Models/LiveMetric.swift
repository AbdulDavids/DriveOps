//
//  LiveMetric.swift
//  DriveOps
//

import Foundation
import SwiftOBD2

enum MetricQuality: Equatable {
    case live
    case recovered
    case waiting
    case invalid(String)
    case stale

    var label: String? {
        switch self {
        case .live: return nil
        case .recovered: return "Checked"
        case .waiting: return "Waiting"
        case .invalid: return "Unavailable"
        case .stale: return "Last reading"
        }
    }
}

struct LiveMetric: Identifiable, Equatable {
    let id: String                 // Stable command identity, e.g. 010C
    let name: String               // Never use an upstream display string as identity
    let category: String
    let value: Double?
    let unit: String
    let updatedAt: Date
    let quality: MetricQuality

    var isUsable: Bool { value != nil && quality != .stale }

    func markedStale() -> LiveMetric {
        .init(id: id, name: name, category: category, value: value, unit: unit, updatedAt: updatedAt, quality: .stale)
    }
}

enum MetricCatalog {
    struct Definition {
        let name: String
        let category: String
        let decimals: Int
        let protocolRange: ClosedRange<Double>?
    }

    private static let definitions: [String: Definition] = [
        "010C": .init(name: "Engine RPM", category: "Engine", decimals: 0, protocolRange: 0...16_383.75),
        "010D": .init(name: "Vehicle Speed", category: "Engine", decimals: 0, protocolRange: 0...255),
        "0105": .init(name: "Coolant Temperature", category: "Temperatures", decimals: 0, protocolRange: -40...215),
        "0104": .init(name: "Engine Load", category: "Engine", decimals: 0, protocolRange: 0...100),
        "0111": .init(name: "Throttle Position", category: "Engine", decimals: 0, protocolRange: 0...100),
        "010F": .init(name: "Intake Air Temperature", category: "Temperatures", decimals: 0, protocolRange: -40...215),
        "0110": .init(name: "Mass Air Flow", category: "Air & fuel", decimals: 1, protocolRange: 0...655.35),
        "010B": .init(name: "Intake Manifold Pressure", category: "Air & fuel", decimals: 0, protocolRange: 0...255),
        "0133": .init(name: "Barometric Pressure", category: "Air & fuel", decimals: 0, protocolRange: 0...255),
        "010E": .init(name: "Timing Advance", category: "Engine", decimals: 1, protocolRange: -64...63.5),
    ]

    static func definition(for command: OBDCommand) -> Definition {
        definitions[command.properties.command] ?? .init(
            name: command.properties.description,
            category: "Other sensors",
            decimals: 1,
            protocolRange: nil
        )
    }

    static func displayName(for command: OBDCommand) -> String { definition(for: command).name }

    static func category(for command: OBDCommand) -> String { definition(for: command).category }

    static func summary(for command: OBDCommand) -> String {
        switch command.properties.command {
        case "010C": return "How fast the engine is turning."
        case "010D": return "Road speed reported by the vehicle."
        case "0105": return "Engine coolant heat level."
        case "0104": return "How hard the engine is working."
        case "0111": return "How far the throttle is open."
        case "010F": return "Temperature of air entering the engine."
        case "0110": return "Air entering the engine each second."
        case "010B": return "Pressure in the intake manifold."
        case "0133": return "Ambient atmospheric pressure."
        case "010E": return "Ignition timing before top dead centre."
        default: return "Live data reported by the vehicle."
        }
    }

    static func placeholder(for command: OBDCommand) -> LiveMetric {
        let definition = definition(for: command)
        return .init(id: command.properties.command, name: definition.name, category: definition.category, value: nil, unit: "", updatedAt: .distantPast, quality: .waiting)
    }

    /// Normalises a decoded dependency result into a stable app reading. This is
    /// deliberately the only boundary where a dependency's labels/value quirks
    /// are interpreted; views receive typed values rather than strings.
    ///
    /// - Parameter batchPIDs: The full set of PID command strings requested in
    ///   the same batch as `command` (e.g. `["010C", "010D", "0105"]`). Needed
    ///   to recover RPM from the PID-echo corruption below — the corrupted top
    ///   byte can be *any* PID sharing this batch, not just RPM's own.
    static func reading(for command: OBDCommand, result: MeasurementResult, at time: Date = .now, batchPIDs: Set<String> = []) -> LiveMetric {
        let definition = definition(for: command)
        let commandID = command.properties.command
        var value = result.value
        var quality: MetricQuality = .live

        // EVMSwiftOBD2 revision e73d56a's batch path can pass another PID's
        // echo byte into the RPM decoder instead of RPM's own — any PID
        // sharing the batch can end up as the corrupted three-byte value's
        // top byte, not just 0C. Recover the two payload bytes here until the
        // dependency is updated; do not infer a correction from an arbitrary
        // large number that doesn't match a PID actually in this batch.
        if commandID == "010C" {
            let batchPIDBytes = Set(batchPIDs.compactMap { UInt8($0.suffix(2), radix: 16) })
            let normalised = normaliseRPMValue(value, knownPIDBytes: batchPIDBytes)
            value = normalised.value
            if normalised.recovered {
                quality = .recovered
            }
        }

        if !value.isFinite {
            return .init(id: commandID, name: definition.name, category: definition.category, value: nil, unit: result.unit.symbol, updatedAt: time, quality: .invalid("The adapter returned a non-numeric value."))
        }
        if let range = definition.protocolRange, !range.contains(value) {
            return .init(id: commandID, name: definition.name, category: definition.category, value: nil, unit: result.unit.symbol, updatedAt: time, quality: .invalid("This reading is outside the protocol range."))
        }
        return .init(id: commandID, name: definition.name, category: definition.category, value: value, unit: result.unit.symbol, updatedAt: time, quality: quality)
    }

    static func format(_ metric: LiveMetric) -> String {
        guard let value = metric.value else { return "—" }
        let decimals = definitions[metric.id]?.decimals ?? 1
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return "\(formatter.string(from: value as NSNumber) ?? "—") \(metric.unit)"
    }

    /// Returns a corrected RPM only when the three-byte batch-decoder shape's
    /// top byte matches a PID actually requested in the same batch (RPM's own
    /// 0x0C, or another requested PID whose echo leaked in). Ordinary large
    /// values, and any top byte not in `knownPIDBytes`, are never guessed at
    /// or altered. `knownPIDBytes` defaults to just 0x0C (RPM's own byte) so
    /// callers that don't have batch context still get the original, narrower
    /// recovery.
    static func normaliseRPMValue(_ value: Double, knownPIDBytes: Set<UInt8> = [0x0C]) -> (value: Double, recovered: Bool) {
        let raw = Int((value * 4).rounded())
        let topByte = UInt8((raw >> 16) & 0xFF)
        guard raw >> 16 == Int(topByte), knownPIDBytes.contains(topByte) else { return (value, false) }
        return (Double(raw & 0xFFFF) / 4, true)
    }

    static func simulated(name: String, value: Double, unit: String, at time: Date = .now) -> LiveMetric {
        let matching = definitions.first { $0.value.name == name }
        let definition = matching?.value ?? .init(name: name, category: "Other sensors", decimals: 1, protocolRange: nil)
        return .init(id: matching?.key ?? "demo.\(name)", name: definition.name, category: definition.category, value: value, unit: unit, updatedAt: time, quality: .live)
    }
}
