//
//  DashboardViewModel.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

@MainActor
extension OBDViewModel {
    var statusColor: Color {
        switch connectionState {
        case .connectedToVehicle: return .green
        case .connectedToAdapter: return .yellow
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    var statusLabel: String {
        switch connectionState {
        case .disconnected: return "Disconnected"
        case .connecting:
            if let type = activeConnectionType {
                return "Connecting via \(type.rawValue)…"
            }
            return "Connecting…"
        case .connectedToAdapter: return "Connected to adapter"
        case .connectedToVehicle:
            if let manufacturer = decodedVIN?.manufacturer {
                return "Connected to \(manufacturer)"
            }
            return "Connected to vehicle"
        case .error: return "Error"
        }
    }
}
