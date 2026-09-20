//
//  PIDPickerView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

@MainActor
struct PIDPickerView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case available = "Available"
        case all = "All sensors"
        case added = "On dashboard"
        var id: Self { self }
    }

    @ObservedObject var vm: OBDViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scope: Scope = .available
    @State private var search = ""

    /// The OBD service batches up to six mode-01 PIDs in one request. More
    /// sensors still work, but require another round trip and refresh slower.
    private static let sensorsPerRequest = 6

    private var selectedCount: Int { vm.dashboardMetricIDs.count }
    private var requestGroups: Int {
        Int((Double(selectedCount) / Double(Self.sensorsPerRequest)).rounded(.up))
    }

    private var supportedByVehicle: Set<OBDCommand>? {
        guard let supported = vm.obdInfo?.supportedPIDs else { return nil }
        return Set(supported)
    }

    private var effectiveScope: Scope {
        supportedByVehicle == nil && scope == .available ? .all : scope
    }

    private var filtered: [OBDCommand] {
        PIDCatalog.allLivePIDs.filter { pid in
            let added = vm.dashboardMetricIDs.contains(pid.properties.command)
            let available = supportedByVehicle?.contains(pid) == true || vm.liveMetrics[pid.properties.command]?.value != nil
            let inScope: Bool
            switch effectiveScope {
            case .available: inScope = available
            case .all: inScope = true
            case .added: inScope = added
            }
            let searchText = [MetricCatalog.displayName(for: pid), MetricCatalog.summary(for: pid), pid.properties.description, pid.properties.command]
                .joined(separator: " ")
            return inScope && (search.isEmpty || searchText.localizedCaseInsensitiveContains(search))
        }
    }

    private var grouped: [(String, [OBDCommand])] {
        let order = ["Engine", "Temperatures", "Air & fuel", "Electrical", "Emissions", "Other sensors"]
        return order.compactMap { category in
            let items = filtered.filter { MetricCatalog.category(for: $0) == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases) { scope in Text(scope.rawValue).tag(scope) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Sensor filter")
            }

            if grouped.isEmpty {
                ContentUnavailableView(
                    effectiveScope == .available ? "No reported sensors" : "No matching sensors",
                    systemImage: "sensor.tag.radiowaves.forward",
                    description: Text(effectiveScope == .available ? "Your vehicle has not reported supported sensors yet. Try All sensors to choose one manually." : "Try a different search or filter.")
                )
            }

            ForEach(grouped, id: \.0) { category, sensors in
                Section(category) {
                    ForEach(sensors, id: \.self) { pid in
                        Button { toggle(pid) } label: { row(for: pid) }
                            .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Text("Adding a sensor puts it on your dashboard and begins requesting it. A sensor marked supported may still take a moment to return a reading.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search, prompt: "Search sensors")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("\(selectedCount) selected", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(selectedCount == 1 ? "1 request group" : "\(max(requestGroups, 1)) request groups")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selectedCount > Self.sensorsPerRequest {
                    Label("More than \(Self.sensorsPerRequest) sensors means updates rotate through \(requestGroups) groups and refresh less often.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Up to \(Self.sensorsPerRequest) sensors update in the same request.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("Add sensors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add all visible") { filtered.forEach { vm.addToDashboard($0) } }
                    Divider()
                    Button("Essentials") { apply(PIDCatalog.defaultSelection) }
                    Button("Warm-up") { apply(PIDCatalog.warmUpSelection) }
                    Button("Air & fuel") { apply(PIDCatalog.airAndFuelSelection) }
                    Divider()
                    Button("Remove all sensors", role: .destructive) {
                        vm.dashboardMetricIDs = []
                        vm.selectedPIDs = []
                    }
                } label: { Image(systemName: "ellipsis.circle") }
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

    private func apply(_ selection: Set<OBDCommand>) {
        vm.dashboardMetricIDs = selection.map(\.properties.command).sorted()
        vm.selectedPIDs = selection
    }

    private func availability(for pid: OBDCommand) -> (String, Color) {
        if let metric = vm.liveMetrics[pid.properties.command] {
            switch metric.quality {
            case .live, .recovered: return ("Responding", .green)
            case .waiting: return ("Waiting", .secondary)
            case .stale: return ("Last reading", .orange)
            case .invalid: return ("Unavailable", .orange)
            }
        }
        if supportedByVehicle?.contains(pid) == true { return ("Supported", .green) }
        return ("Not checked", .secondary)
    }

    private func row(for pid: OBDCommand) -> some View {
        let added = vm.dashboardMetricIDs.contains(pid.properties.command)
        let availability = availability(for: pid)
        let reading = vm.liveMetrics[pid.properties.command]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(added ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(MetricCatalog.displayName(for: pid)).foregroundStyle(.primary)
                    Spacer()
                    Text(added ? "Added" : availability.0)
                        .font(.caption.weight(.medium)).foregroundStyle(added ? Color.accentColor : availability.1)
                }
                Text(reading.map(MetricCatalog.format) ?? MetricCatalog.summary(for: pid))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(pid.properties.command)
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle()).padding(.vertical, 3)
    }
}

#if DEBUG
#Preview("Sensor catalogue") {
    NavigationStack { PIDPickerView(vm: .stub(state: .disconnected)) }
}
#endif
