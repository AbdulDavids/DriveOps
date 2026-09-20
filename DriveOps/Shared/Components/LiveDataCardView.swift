//
//  LiveDataCardView.swift
//  DriveOps
//

import SwiftUI
import SwiftOBD2

/// Dashboard membership is a deliberate user choice, independent of what is
/// temporarily being polled or compared.
struct LiveDataCardView: View {
    @ObservedObject var vm: OBDViewModel
    var isWide: Bool = false

    @State private var isEditing = false
    @State private var showSensors = false
    @State private var showComparison = false
    @State private var selectedMetric: LiveMetric?

    private var dashboardMetrics: [LiveMetric] {
        vm.dashboardMetricIDs.compactMap { command in
            guard let pid = PIDCatalog.command(named: command) else { return nil }
            return vm.liveMetrics[command] ?? MetricCatalog.placeholder(for: pid)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: isWide ? 3 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dashboard").font(.title3.weight(.semibold))
                    Text("Your chosen live sensors").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .buttonStyle(.bordered).controlSize(.small)
            }

            if dashboardMetrics.isEmpty {
                ContentUnavailableView("Add a sensor", systemImage: "plus.circle", description: Text("Choose the readings you want to keep on your dashboard."))
                Button("Browse sensors") { showSensors = true }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            } else if isEditing {
                DashboardEditor(vm: vm)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(dashboardMetrics) { metric in
                        MetricTile(metric: metric, history: vm.metricHistory[metric.name] ?? []) {
                            selectedMetric = metric
                        }
                    }
                }
                HStack {
                    Button { showSensors = true } label: { Label("Add sensor", systemImage: "plus") }
                        .buttonStyle(.bordered)
                    Spacer()
                    if dashboardMetrics.count >= 2 {
                        Button { showComparison = true } label: { Label("Compare", systemImage: "chart.line.uptrend.xyaxis") }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showSensors) { NavigationStack { PIDPickerView(vm: vm) } }
        .sheet(isPresented: $showComparison) { MetricComparisonView(vm: vm) }
        .sheet(item: $selectedMetric) { metric in
            SensorDetailView(metric: metric, history: vm.metricHistory[metric.name] ?? [])
        }
    }
}

private struct MetricTile: View {
    let metric: LiveMetric
    let history: [MetricSample]
    let action: () -> Void

    private var status: String? {
        if let quality = metric.quality.label { return quality }
        if metric.updatedAt == .distantPast { return "Waiting" }
        if Date().timeIntervalSince(metric.updatedAt) > 2 { return "Last reading" }
        return nil
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(metric.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    if let status { Text(status).font(.caption2.weight(.medium)).foregroundStyle(.secondary) }
                }
                Text(MetricCatalog.format(metric))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(metric.value == nil ? .secondary : .primary)
                    .minimumScaleFactor(0.65).lineLimit(1)
                if history.count > 1 {
                    MetricSparkline(samples: history).frame(height: 26)
                } else {
                    Text(metric.value == nil ? "Waiting for a valid response" : "Live")
                        .font(.caption2).foregroundStyle(.secondary).frame(height: 26, alignment: .leading)
                }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).accessibilityHint("Opens sensor details")
    }
}

@MainActor
private struct DashboardEditor: View {
    @ObservedObject var vm: OBDViewModel

    var body: some View {
        List {
            Section("Shown on your dashboard") {
                ForEach(vm.dashboardMetricIDs, id: \.self) { command in
                    HStack {
                        Text(PIDCatalog.command(named: command).map(MetricCatalog.displayName(for:)) ?? command)
                        Spacer()
                        Button(role: .destructive) { vm.removeFromDashboard(command) } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain).accessibilityLabel("Remove sensor")
                    }
                }
                .onMove(perform: vm.moveDashboardMetric)
            }
        }
        .frame(minHeight: 220)
    }
}

struct MetricSparkline: View {
    let samples: [MetricSample]
    var body: some View {
        GeometryReader { geometry in
            let values = samples.map(\.value)
            let low = values.min() ?? 0
            let high = values.max() ?? low + 1
            let span = max(high - low, 0.0001)
            Path { path in
                for (index, sample) in samples.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(samples.count - 1, 1))
                    let y = geometry.size.height * (1 - CGFloat((sample.value - low) / span))
                    index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SensorDetailView: View {
    let metric: LiveMetric
    let history: [MetricSample]
    @Environment(\.dismiss) private var dismiss

    private var average: Double? {
        guard !history.isEmpty else { return nil }
        return history.map(\.value).reduce(0, +) / Double(history.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(MetricCatalog.format(metric))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text(metric.quality.label ?? "Live").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    if history.count > 1 {
                        MetricSparkline(samples: history).frame(height: 180).padding()
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                        HStack {
                            DetailStatistic("Min", history.map(\.value).min())
                            DetailStatistic("Average", average)
                            DetailStatistic("Max", history.map(\.value).max())
                        }
                    } else {
                        ContentUnavailableView("Building history", systemImage: "chart.line.uptrend.xyaxis", description: Text("Leave this sensor open while DriveOps collects a few readings."))
                    }

                    Text(metric.category).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Values are decoded and checked before they appear here. Open Settings for connection logs if this sensor is unavailable.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle(metric.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct DetailStatistic: View {
    let label: String
    let value: Double?
    init(_ label: String, _ value: Double?) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { String(format: "%.1f", $0) } ?? "—").font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
private func redesignPreviewViewModel() -> OBDViewModel {
    let vm = OBDViewModel.stub(
        state: .connectedToVehicle,
        liveData: [
            "Engine RPM": "1,073 rpm",
            "Vehicle Speed": "87 km/h",
            "Coolant Temperature": "91 °C",
            "Engine Load": "42 %",
        ]
    )
    vm.dashboardMetricIDs = ["010C", "010D", "0105", "0104"]
    return vm
}

#Preview("Redesigned dashboard") {
    NavigationStack {
        ScrollView {
            LiveDataCardView(vm: redesignPreviewViewModel())
                .padding()
        }
        .navigationTitle("DriveOps")
    }
}

#Preview("Sensor detail") {
    SensorDetailView(
        metric: MetricCatalog.simulated(name: "Engine RPM", value: 1_073, unit: "rpm"),
        history: (0..<24).map { index in
            MetricSample(
                timestamp: Date.now.addingTimeInterval(Double(index - 24) * 3),
                value: 850 + Double(index) * 18 + Double(index % 4) * 35
            )
        }
    )
}

#Preview("Waiting for a sensor") {
    let vm = OBDViewModel.stub(state: .connectedToVehicle)
    vm.dashboardMetricIDs = ["010C"]
    return LiveDataCardView(vm: vm).padding()
}
#endif
