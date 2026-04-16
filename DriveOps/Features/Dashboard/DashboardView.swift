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
