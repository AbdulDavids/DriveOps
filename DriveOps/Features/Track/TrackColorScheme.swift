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

    /// A fixed, distinct color per sensor slot (0...3). Solid schemes use the
    /// same accent for every slot; rainbow gives each field its own color,
    /// F1-dash style.
    func fieldColor(_ index: Int) -> Color {
        guard self == .rainbow else { return accent }
        let palette: [Color] = [
            Color(red: 0.98, green: 0.24, blue: 0.24), // red
            Color(red: 1.0, green: 0.75, blue: 0.15),  // amber
            Color(red: 0.24, green: 0.95, blue: 0.98), // cyan
            Color(red: 0.4, green: 0.85, blue: 0.3),   // green
        ]
        return palette[index % palette.count]
    }

    /// Color for the lap timer card. Solid schemes use the accent; rainbow uses a fifth color.
    var timingColor: Color {
        guard self == .rainbow else { return accent }
        return Color(red: 0.7, green: 0.4, blue: 1.0) // purple
    }
}
