//
//  ConnectionCardView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct ConnectionCardView: View {
    @ObservedObject var vm: OBDViewModel
    @Binding var showWifiSheet: Bool
    @Binding var showBTSheet: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(vm.statusColor)
                    .frame(width: 10, height: 10)
                Text(vm.statusLabel)
                    .font(.subheadline)
                Spacer()

                if vm.isConnecting {
                    Button(action: { vm.cancelConnection() }) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                } else if vm.connectionState == .connectedToVehicle {
                    Button("Disconnect", role: .destructive) {
                        vm.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if vm.connectionState != .connectedToVehicle && !vm.isConnecting {
                HStack(spacing: 12) {
                    Button(action: { showBTSheet = true }) {
                        Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button(action: { showWifiSheet = true }) {
                        Label("Wi-Fi", systemImage: "wifi")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }

            #if targetEnvironment(simulator)
            Label("Simulator: BT & WiFi use mock data", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #endif
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
