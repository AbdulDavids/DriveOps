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
                Text("Sensors")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(vm.dashboardMetricIDs.count) sensors on your dashboard. Add or remove a sensor here; updates apply immediately.")
                    if requestsPerCycle > 1 {
                        Text("That's \(requestsPerCycle) requests per poll cycle (adapters answer at most \(Self.pidsPerRequest) PIDs per request) — more selected PIDs means slower updates.")
                    }
                    if supportedByVehicle != nil {
                        Text("A star means your vehicle reported the sensor as supported. Unmarked sensors can still work on some vehicles.")
                    }
                }
            }
        }
        .navigationTitle("Add sensors")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add all sensors") {
                        PIDCatalog.allLivePIDs.forEach { vm.addToDashboard($0) }
                    }
                    Button("Restore essentials") {
                        vm.dashboardMetricIDs = PIDCatalog.defaultSelection.map(\.properties.command).sorted()
                        vm.selectedPIDs = PIDCatalog.defaultSelection
                    }
                    Button("Remove all sensors", role: .destructive) {
                        vm.dashboardMetricIDs = []
                        vm.selectedPIDs = []
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func toggle(_ pid: OBDCommand) {
        if vm.dashboardMetricIDs.contains(pid.properties.command) {
            vm.removeFromDashboard(pid.properties.command)
        } else {
            vm.addToDashboard(pid)
        }
    }

    private func row(for pid: OBDCommand) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vm.dashboardMetricIDs.contains(pid.properties.command) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(vm.dashboardMetricIDs.contains(pid.properties.command) ? Color.accentColor : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                Text(MetricCatalog.displayName(for: pid))
                        .foregroundStyle(.primary)
                    if let supportedByVehicle, supportedByVehicle.contains(pid) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text("\(pid.properties.description) · \(pid.properties.command)")
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
