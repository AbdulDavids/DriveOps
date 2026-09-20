//
//  LiveMetric.swift
//  DriveOps
//

import Foundation
import SwiftOBD2

enum MetricQuality: Equatable {
    case live
    case recovered
    case invalid(String)
    case stale

    var label: String? {
        switch self {
        case .live: return nil
        case .recovered: return "Checked"
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

    static func placeholder(for command: OBDCommand) -> LiveMetric {
        let definition = definition(for: command)
        return .init(id: command.properties.command, name: definition.name, category: definition.category, value: nil, unit: "", updatedAt: .distantPast, quality: .invalid("Waiting for a reading."))
    }

    /// Normalises a decoded dependency result into a stable app reading. This is
    /// deliberately the only boundary where a dependency's labels/value quirks
    /// are interpreted; views receive typed values rather than strings.
    static func reading(for command: OBDCommand, result: MeasurementResult, at time: Date = .now) -> LiveMetric {
        let definition = definition(for: command)
        let commandID = command.properties.command
        var value = result.value
        var quality: MetricQuality = .live

        // EVMSwiftOBD2 revision e73d56a's batch path passes the PID echo into
        // the RPM decoder. Its three-byte value has 0C as the top byte. Recover
        // the two payload bytes here until the dependency is updated; do not
        // infer a correction from an arbitrary large number.
        if commandID == "010C" {
            let raw = Int((value * 4).rounded())
            if raw >> 16 == 0x0C {
                value = Double(raw & 0xFFFF) / 4
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

    static func simulated(name: String, value: Double, unit: String, at time: Date = .now) -> LiveMetric {
        let matching = definitions.first { $0.value.name == name }
        let definition = matching?.value ?? .init(name: name, category: "Other sensors", decimals: 1, protocolRange: nil)
        return .init(id: matching?.key ?? "demo.\(name)", name: definition.name, category: definition.category, value: value, unit: unit, updatedAt: time, quality: .live)
    }
}
