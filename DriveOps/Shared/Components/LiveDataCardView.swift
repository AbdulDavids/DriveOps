//
//  LiveDataCardView.swift
//  DriveOps
//

import SwiftUI

struct LiveDataCardView: View {
    @ObservedObject var vm: OBDViewModel
    var isWide: Bool = false

    @State private var pinnedKeys: Set<String> = []
    @State private var showCompare = false
    @State private var showGauges = false
    @State private var showPIDPicker = false

    private var liveData: [String: String] { vm.liveData }
    private var metricHistory: [String: [MetricSample]] { vm.metricHistory }

    private let maxPins = 4

    private var sorted: [(key: String, value: String)] {
        liveData.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live Data", systemImage: "gauge.with.needle")
                    .font(.headline)
                Spacer()
                Button {
                    showPIDPicker = true
                } label: {
                    Label("PIDs", systemImage: "list.bullet.circle")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button {
                    showGauges = true
                } label: {
                    Label("Gauges", systemImage: "gauge.open.with.lines.needle.33percent")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                if pinnedKeys.count >= 2 {
                    Button {
                        showCompare = true
                    } label: {
                        Label("Compare (\(pinnedKeys.count))", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: pinnedKeys.count)

            Divider()

            if sorted.isEmpty {
                emptySelectionPrompt
            } else if isWide {
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(sorted, id: \.key) { key, value in
                        MetricChartView(
                            label: key,
                            value: value,
                            history: metricHistory[key] ?? [],
                            isPinned: pinnedKeys.contains(key),
                            onPin: { toggle(key) }
                        )
                    }
                }
            } else {
                ForEach(sorted, id: \.key) { key, value in
                    MetricChartView(
                        label: key,
                        value: value,
                        history: metricHistory[key] ?? [],
                        isPinned: pinnedKeys.contains(key),
                        onPin: { toggle(key) }
                    )
                }
            }

            if !pinnedKeys.isEmpty {
                HStack {
                    Text(pinnedKeys.count == 1
                         ? "Long-press a metric to add to compare"
                         : "\(pinnedKeys.count) selected — up to \(maxPins)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { pinnedKeys.removeAll() }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: pinnedKeys)
        .adaptivePresentation(isPresented: $showCompare) {
            let keys = Array(pinnedKeys).sorted()
            CompareSheet(
                keys: keys,
                histories: keys.reduce(into: [:]) { $0[$1] = metricHistory[$1] ?? [] }
            )
        }
        .adaptivePresentation(isPresented: $showGauges) {
            let hasPins = !pinnedKeys.isEmpty
            let filteredData = hasPins ? liveData.filter { pinnedKeys.contains($0.key) } : liveData
            GaugeGridView(liveData: filteredData, fillScreen: hasPins)
        }
        .adaptivePresentation(isPresented: $showPIDPicker) {
            NavigationStack {
                PIDPickerView(vm: vm)
            }
        }
    }

    // Shown instead of the metric list when selectedPIDs is empty — the card
    // still needs to render (rather than DashboardView hiding it entirely
    // when liveData.isEmpty) so there's always a way back to the picker.
    private var emptySelectionPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No PIDs selected")
                .font(.subheadline.weight(.medium))
            Text("Choose which sensors to poll for live data.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Select PIDs") { showPIDPicker = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func toggle(_ key: String) {
        if pinnedKeys.contains(key) {
            pinnedKeys.remove(key)
        } else if pinnedKeys.count < maxPins {
            pinnedKeys.insert(key)
        }
    }
}
