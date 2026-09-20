//
//  PIDPickerView.swift
//  DriveOps
//
//  Lets the user choose which PIDs the live-data poll requests, replacing
//  the old fixed 10-PID list — see Models/PIDSelection.swift.
//

import SwiftUI
import SwiftOBD2

struct PIDPickerView: View {
    @ObservedObject var vm: OBDViewModel
    @Environment(\.dismiss) private var dismiss

    // Mirrors the fork's OBDService.requestPIDs chunk size (SAE J1979's
    // per-request PID limit under CAN framing — see the fork's
    // Sources/SwiftOBD2/obd2service.swift). Not enforced as a hard cap here:
    // selecting more just costs more round-trips per 300ms poll cycle, which
    // is what this hint is telling the user rather than blocking them.
    private static let pidsPerRequest = 6

    private var supportedByVehicle: Set<OBDCommand>? {
        guard let supported = vm.obdInfo?.supportedPIDs else { return nil }
        return Set(supported)
    }

    private var requestsPerCycle: Int {
        guard !vm.selectedPIDs.isEmpty else { return 0 }
        return Int((Double(vm.selectedPIDs.count) / Double(Self.pidsPerRequest)).rounded(.up))
    }

    var body: some View {
        List {
            Section {
                ForEach(PIDCatalog.allLivePIDs, id: \.self) { pid in
                    Button {
                        toggle(pid)
                    } label: {
                        row(for: pid)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Live Data PIDs")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(vm.selectedPIDs.count) of \(PIDCatalog.allLivePIDs.count) selected. Changes apply immediately — no need to reconnect.")
                    if requestsPerCycle > 1 {
                        Text("That's \(requestsPerCycle) requests per poll cycle (adapters answer at most \(Self.pidsPerRequest) PIDs per request) — more selected PIDs means slower updates.")
                    }
                    if supportedByVehicle != nil {
                        Text("A star marks PIDs your connected vehicle reported as supported. Unmarked PIDs may still work — vehicles don't always report every PID they answer.")
                    }
                }
            }
        }
        .navigationTitle("PID Selection")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Select All") { vm.selectedPIDs = Set(PIDCatalog.allLivePIDs) }
                    Button("Restore Defaults") { vm.selectedPIDs = PIDCatalog.defaultSelection }
                    Button("Deselect All", role: .destructive) { vm.selectedPIDs = [] }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func toggle(_ pid: OBDCommand) {
        if vm.selectedPIDs.contains(pid) {
            vm.selectedPIDs.remove(pid)
        } else {
            vm.selectedPIDs.insert(pid)
        }
    }

    private func row(for pid: OBDCommand) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vm.selectedPIDs.contains(pid) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(vm.selectedPIDs.contains(pid) ? Color.accentColor : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(pid.properties.description)
                        .foregroundStyle(.primary)
                    if let supportedByVehicle, supportedByVehicle.contains(pid) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(pid.properties.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        PIDPickerView(vm: .stub(state: .disconnected))
    }
}
#endif
