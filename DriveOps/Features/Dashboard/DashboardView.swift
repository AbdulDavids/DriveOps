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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ConnectionCardView(vm: vm, showWifiSheet: $showWifiSheet, showBTSheet: $showBTSheet)

                    if let info = vm.obdInfo {
                        VehicleInfoCardView(info: info)
                    }

                    if !vm.liveData.isEmpty {
                        LiveDataCardView(liveData: vm.liveData)
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
