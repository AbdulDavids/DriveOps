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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ConnectionCardView(vm: vm, showWifiSheet: $showWifiSheet, showBTSheet: $showBTSheet)

                    if !vm.liveData.isEmpty {
                        LiveDataCardView(liveData: vm.liveData, metricHistory: vm.metricHistory, isWide: isWide)
                    }

                    if isWide && !vm.liveData.isEmpty {
                        KeyGaugesRow(liveData: vm.liveData)
                    }

                    if let info = vm.obdInfo {
                        VehicleInfoCardView(info: info)
                    }

                    if vm.connectionState == .disconnected && !vm.isConnecting {
                        DemoModePrompt { vm.connectDemo() }
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
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// MARK: - Key Gauges Row (iPad only)

private struct KeyGaugesRow: View {
    let liveData: [String: String]

    private let keys = ["Engine RPM", "Vehicle Speed", "Engine Load"]
    private let colors: [Color] = [.accentColor, .orange, .green]

    private func parsed(_ value: String) -> Double {
        Double(value.components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted).joined()) ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
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
