//
//  MetricComparisonView.swift
//  DriveOps
//

import SwiftUI
import Charts
import SwiftOBD2

/// Keeps each sensor on its own physical scale. A comparison should reveal
/// readings, rather than making different units look comparable by silently
/// normalising them into one line chart.
struct MetricComparisonView: View {
    @ObservedObject var vm: OBDViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>

    init(vm: OBDViewModel) {
        self.vm = vm
        _selectedIDs = State(initialValue: Set(vm.dashboardMetricIDs.prefix(2)))
    }

    private var available: [(command: String, metric: LiveMetric)] {
        vm.dashboardMetricIDs.compactMap { command in
            guard let pid = PIDCatalog.command(named: command) else { return nil }
            return (command, vm.liveMetrics[command] ?? MetricCatalog.placeholder(for: pid))
        }
    }

    private var selected: [(command: String, metric: LiveMetric)] {
        available.filter { selectedIDs.contains($0.command) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Compare sensors")
                            .font(.title3.weight(.semibold))
                        Text("Each chart keeps its real unit and scale.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(available, id: \.command) { item in
                            Button {
                                toggle(item.command)
                            } label: {
                                Label(item.metric.name, systemImage: selectedIDs.contains(item.command) ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedIDs.contains(item.command) ? .accentColor : .secondary)
                            .controlSize(.small)
                        }
                    }

                    if selected.isEmpty {
                        ContentUnavailableView("Choose sensors", systemImage: "chart.line.uptrend.xyaxis", description: Text("Select up to four dashboard sensors to compare their recent history."))
                    } else {
                        ForEach(selected, id: \.command) { item in
                            ComparisonChart(metric: item.metric, history: vm.metricHistory[item.metric.name] ?? [])
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func toggle(_ command: String) {
        if selectedIDs.contains(command) {
            selectedIDs.remove(command)
        } else if selectedIDs.count < 4 {
            selectedIDs.insert(command)
        }
    }
}

private struct ComparisonChart: View {
    let metric: LiveMetric
    let history: [MetricSample]

    private var bounds: ClosedRange<Double> {
        let values = history.map(\.value)
        let min = values.min() ?? 0
        let max = values.max() ?? 1
        return min...(max == min ? min + 1 : max)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(metric.name).font(.headline)
                Spacer()
                Text(MetricCatalog.format(metric)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if history.count > 1 {
                Chart(history) { sample in
                    LineMark(x: .value("Time", sample.timestamp), y: .value(metric.unit, sample.value))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.linear)
                }
                .chartYScale(domain: bounds)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisGridLine(); AxisValueLabel(format: .dateTime.minute().second()) } }
                .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel() } }
                .frame(height: 180)
            } else {
                Text("Building history…").font(.caption).foregroundStyle(.secondary).frame(height: 100, alignment: .leading)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A small wrapping layout for the sensor chips above the charts.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
#Preview("Comparison") {
    let vm = OBDViewModel.stub(state: .connectedToVehicle, liveData: [
        "Engine RPM": "1,073 rpm", "Vehicle Speed": "87 km/h"
    ])
    vm.dashboardMetricIDs = ["010C", "010D"]
    return MetricComparisonView(vm: vm)
}
#endif
