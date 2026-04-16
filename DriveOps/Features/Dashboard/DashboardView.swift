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
                    if isWide {
                        HStack(alignment: .top, spacing: 20) {
                            ConnectionCardView(vm: vm, showWifiSheet: $showWifiSheet, showBTSheet: $showBTSheet)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            if let info = vm.obdInfo {
                                VehicleInfoCardView(info: info)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                    } else {
                        ConnectionCardView(vm: vm, showWifiSheet: $showWifiSheet, showBTSheet: $showBTSheet)
                        if let info = vm.obdInfo {
                            VehicleInfoCardView(info: info)
                        }
                    }

                    if !vm.liveData.isEmpty {
                        LiveDataCardView(liveData: vm.liveData, isWide: isWide)
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
