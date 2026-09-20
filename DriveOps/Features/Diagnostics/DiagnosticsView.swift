//
//  DiagnosticsView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2
import VIN

struct DiagnosticsView: View {
    @ObservedObject var vm: OBDViewModel
    @State private var searchText = ""
    @State private var selectedCode: TroubleCode?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    var isWide: Bool { hSizeClass == .regular }

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
        if isWide {
            NavigationSplitView {
                codeList
                    .navigationTitle("Diagnostics")
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search codes or descriptions")
                    .toolbar { toolbarContent }
            } detail: {
                if let selected = selectedCode,
                   let item = allCodes.first(where: { $0.code == selected }) {
                    TroubleCodeDetailView(code: item.code, ecu: item.ecu, vm: vm)
                } else {
                    ContentUnavailableView("Select a Code", systemImage: "stethoscope")
                }
            }
        } else {
            NavigationStack {
                codeList
                    .navigationTitle("Diagnostics")
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search codes or descriptions")
                    .toolbar { toolbarContent }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var codeList: some View {
        List(selection: $selectedCode) {
            if let vin = vm.obdInfo?.vin {
                Section {
                    HStack {
                        Label("VIN", systemImage: "number")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(vin)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let manufacturer = vm.decodedVIN?.manufacturer {
                        HStack {
                            Text("Manufacturer")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(manufacturer)
                                .font(.subheadline)
                        }
                    }
                }
            }

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
                    codeRow(item: item)
                        .tag(item.code)
                }
            }
        }
    }

    @ViewBuilder
    private func codeRow(item: (ecu: ECUID, code: TroubleCode)) -> some View {
        if isWide {
            // On iPad, selection drives the split view detail — no NavigationLink needed
            VStack(alignment: .leading, spacing: 4) {
                codeRowContent(item: item)
            }
            .padding(.vertical, 2)
        } else {
            NavigationLink(destination: TroubleCodeDetailView(code: item.code, ecu: item.ecu, vm: vm)) {
                VStack(alignment: .leading, spacing: 4) {
                    codeRowContent(item: item)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func codeRowContent(item: (ecu: ECUID, code: TroubleCode)) -> some View {
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

// MARK: - Previews

#if DEBUG
private func decodeCodes(_ json: String) -> [TroubleCode] {
    (try? JSONDecoder().decode([TroubleCode].self, from: Data(json.utf8))) ?? []
}

private let mockTroubleCodes: [ECUID: [TroubleCode]] = [
    .engine: decodeCodes("""
        [
            {"code":"P0420","description":"Catalyst System Efficiency Below Threshold (Bank 1)"},
            {"code":"P0171","description":"System Too Lean (Bank 1)"}
        ]
        """),
    .transmission: decodeCodes("""
        [{"code":"P0700","description":"Transmission Control System Malfunction"}]
        """),
]

#Preview("Not Connected") {
    DiagnosticsView(vm: .stub(state: .disconnected))
}

#Preview("Scanning") {
    DiagnosticsView(vm: .stub(state: .connectedToVehicle, isScanningCodes: true))
}

#Preview("No Codes") {
    DiagnosticsView(vm: .stub(state: .connectedToVehicle))
}

#Preview("With Codes") {
    DiagnosticsView(vm: .stub(
        state: .connectedToVehicle,
        troubleCodes: mockTroubleCodes
    ))
}

#Preview("Scan Error") {
    DiagnosticsView(vm: .stub(
        state: .connectedToVehicle,
        scanError: "Could not communicate with ECU. Try again."
    ))
}
#endif
