import SwiftUI

enum TrackColorScheme: String, CaseIterable, Identifiable {
    case lime, cyan, amber, magenta, rainbow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lime: return "Lime"
        case .cyan: return "Cyan"
        case .amber: return "Amber"
        case .magenta: return "Magenta"
        case .rainbow: return "Rainbow"
        }
    }

    var accent: Color {
        switch self {
        case .lime: return Color(red: 0.83, green: 0.98, blue: 0.12)
        case .cyan: return Color(red: 0.24, green: 0.95, blue: 0.98)
        case .amber: return Color(red: 1.0, green: 0.75, blue: 0.15)
        case .magenta: return Color(red: 0.98, green: 0.24, blue: 0.75)
        case .rainbow: return Color(red: 0.83, green: 0.98, blue: 0.12)
        }
    }

    /// For rainbow, cycles hue over time; every other scheme returns a fixed color.
    func accent(at date: Date) -> Color {
        guard self == .rainbow else { return accent }
        let period = 6.0
        let hue = (date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)) / period
        return Color(hue: hue, saturation: 0.85, brightness: 1.0)
    }
}
