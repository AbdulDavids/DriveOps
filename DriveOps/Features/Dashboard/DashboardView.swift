//
//  DashboardView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct DashboardView: View {
    @ObservedObject var vm: OBDViewModel
    @Binding var showWifiSheet: Bool
    @Binding var showBTSheet: Bool

    @Environment(\.horizontalSizeClass) private var hSizeClass

    var isWide: Bool { hSizeClass == .regular }

    private var isConnected: Bool { vm.connectionState == .connectedToVehicle }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isConnected {
                        // Connected: the status/disconnect card moves to the
                        // toolbar (see .toolbar below) to free up this space
                        // for the dashboard itself.
                        LiveDataCardView(vm: vm, isWide: isWide)

                        if let info = vm.obdInfo {
                            VehicleInfoCardView(info: info)
                        }
                    } else {
                        // Not connected: nothing to show a dashboard/vehicle
                        // info *for* yet, so only the connect UI renders.
                        ConnectionCardView(vm: vm, showWifiSheet: $showWifiSheet, showBTSheet: $showBTSheet)

                        if vm.connectionState == .disconnected && !vm.isConnecting {
                            DemoModePrompt { vm.connectDemo() }
                        }
                    }

                    if let error = vm.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("DriveOps")
            #if os(iOS)
            // The large title visually competes with the Disconnect button
            // in the same bar once connected, so it collapses to inline only
            // then — disconnected keeps the normal large DriveOps title.
            .navigationBarTitleDisplayMode(isConnected ? .inline : .large)
            #endif
            .toolbar {
                if isConnected {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Disconnect", role: .destructive) {
                            vm.disconnect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

// MARK: - Key Gauges Row (iPad only)

private struct KeyGaugesRow: View {
    let liveData: [String: String]

    static let keys = ["Engine RPM", "Vehicle Speed", "Engine Load"]
    private let colors: [Color] = [.accentColor, .orange, .green]

    static func hasAnyKey(in liveData: [String: String]) -> Bool {
        keys.contains { liveData[$0] != nil }
    }

    private func parsed(_ value: String) -> Double {
        Double(value.components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted).joined()) ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.keys.enumerated()), id: \.element) { index, key in
                if let raw = liveData[key] {
                    let current = parsed(raw)
                    let gMin = MetricGaugeDomain.min(for: key, observed: current)
                    let gMax = MetricGaugeDomain.max(for: key, observed: current)
                    let clamped = Swift.max(gMin, Swift.min(gMax, current))
                    let color = colors[index]

                    VStack(spacing: 8) {
                        Gauge(value: clamped, in: gMin...gMax) {
                            EmptyView()
                        } currentValueLabel: {
                            Text(String(format: "%.0f", current))
                                .font(.system(.title3, design: .rounded).bold())
                                .foregroundStyle(color)
                        } minimumValueLabel: {
                            Text(String(format: "%.0f", gMin))
                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                        } maximumValueLabel: {
                            Text(String(format: "%.0f", gMax))
                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .gaugeStyle(.accessoryCircular)
                        .tint(color)
                        .scaleEffect(1.6)
                        .frame(height: 90)

                        Text(key)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

// MARK: - Demo Mode Prompt

private struct DemoModePrompt: View {
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("No obd scanner thingie (or no car)..?")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(action: onTap) {
                Label("Try Demo Mode", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
