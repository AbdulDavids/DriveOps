//
//  DiagnosticsView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

struct DiagnosticsView: View {
    @ObservedObject var vm: OBDViewModel
    @State private var searchText = ""

    var isConnected: Bool { vm.connectionState == .connectedToVehicle }

    var allCodes: [(ecu: ECUID, code: TroubleCode)] {
        vm.troubleCodes
            .sorted { $0.key.description < $1.key.description }
            .flatMap { ecu, codes in codes.sorted().map { (ecu, $0) } }
    }

    var filteredCodes: [(ecu: ECUID, code: TroubleCode)] {
        guard !searchText.isEmpty else { return allCodes }
        let q = searchText.uppercased()
        return allCodes.filter {
            $0.code.code.contains(q) || $0.code.description.uppercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isConnected {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "car.side.slash",
                        description: Text("Connect to a vehicle to scan for trouble codes.")
                    )
                    .listRowBackground(Color.clear)
                } else if vm.isScanningCodes {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 32)
                } else if allCodes.isEmpty && vm.scanError == nil {
                    ContentUnavailableView(
                        "No Codes",
                        systemImage: "checkmark.seal",
                        description: Text("Tap Refresh to check for diagnostic trouble codes.")
                    )
                    .listRowBackground(Color.clear)
                } else if filteredCodes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                } else {
                    if let error = vm.scanError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }

                    ForEach(filteredCodes, id: \.code) { item in
                        NavigationLink(destination: TroubleCodeDetailView(code: item.code, ecu: item.ecu)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.code.code)
                                        .font(.system(.subheadline, design: .monospaced).bold())
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(item.ecu.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.quaternary, in: Capsule())
                                }
                                Text(item.code.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search codes or descriptions")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !allCodes.isEmpty && !vm.isScanningCodes {
                        Button(role: .destructive) {
                            vm.clearTroubleCodes()
                        } label: {
                            Label("Clear Codes", systemImage: "trash")
                        }
                    }

                    Button {
                        vm.scanTroubleCodes()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!isConnected || vm.isScanningCodes)
                }
            }
        }
    }
}
