//
//  BLEDevicePickerSheet.swift
//  DriveOps
//
//  Lists every nearby BLE peripheral from an unfiltered scan (not just ones
//  the library recognises by service UUID) so the user can pick their own
//  adapter instead of the app silently connecting to whichever one answers
//  first. See docs/architecture/connection-lifecycle.md.
//

import SwiftUI
import CoreBluetooth
import SwiftOBD2

struct BLEDevicePickerSheet: View {
    @ObservedObject var vm: OBDViewModel
    @Binding var isPresented: Bool
    @State private var showingAllDevices = false

    /// Common substrings in cheap ELM327-style OBD2 adapter names (case
    /// folded before matching) — narrows a noisy BLE scan to the devices
    /// someone actually came here for, with "Show All Devices" as the escape
    /// hatch for anything unusually named.
    nonisolated private static let likelyNameKeywords = ["obd", "elm", "vlink", "obdlink"]

    nonisolated private static func isLikelyOBD2Device(_ peripheral: CBPeripheral) -> Bool {
        guard let name = peripheral.name?.lowercased() else { return false }
        return Self.likelyNameKeywords.contains { name.contains($0) }
    }

    private var displayedPeripherals: [CBPeripheral] {
        guard !showingAllDevices else { return vm.discoveredPeripherals }
        let likely = vm.discoveredPeripherals.filter(Self.isLikelyOBD2Device)
        return likely.isEmpty ? vm.discoveredPeripherals : likely
    }

    private var isFiltering: Bool {
        !showingAllDevices && displayedPeripherals.count < vm.discoveredPeripherals.count
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Choose a Device")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            vm.stopPeripheralScan()
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if vm.isScanningForPeripherals {
                            ProgressView()
                        } else {
                            Button("Search Again") {
                                vm.startPeripheralScan()
                            }
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear { vm.startPeripheralScan() }
        .onDisappear { vm.stopPeripheralScan() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.discoveredPeripherals.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    ForEach(displayedPeripherals, id: \.identifier) { peripheral in
                        Button {
                            vm.connect(to: peripheral)
                            isPresented = false
                        } label: {
                            deviceRow(peripheral)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    if isFiltering {
                        Button("Show All Devices") {
                            withAnimation { showingAllDevices = true }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private func deviceRow(_ peripheral: CBPeripheral) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cable.connector")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(peripheral.name ?? "Unnamed device")
                    .font(.body.weight(.medium))
                Text(peripheral.identifier.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if vm.isScanningForPeripherals {
                ProgressView()
                    .controlSize(.large)
                Text("Searching for nearby devices…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No devices found")
                    .font(.headline)
                Text("Make sure your adapter is plugged in and the car's ignition is on, then try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Search Again") {
                    vm.startPeripheralScan()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Scanning") {
    BLEDevicePickerSheet(vm: .stub(state: .disconnected), isPresented: .constant(true))
}
#endif
