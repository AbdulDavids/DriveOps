//
//  LiveDataCardView.swift
//  DriveOps
//

import SwiftUI

struct LiveDataCardView: View {
    let liveData: [String: String]
    let metricHistory: [String: [MetricSample]]
    var isWide: Bool = false

    @State private var pinnedKeys: Set<String> = []
    @State private var showCompare = false
    @State private var showGauges = false

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
                    showGauges = true
                } label: {
                    Image(systemName: "gauge.open.with.lines.needle.33percent")
                        .font(.caption)
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

            if isWide {
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
        .sheet(isPresented: $showCompare) {
            let keys = Array(pinnedKeys).sorted()
            CompareSheet(
                keys: keys,
                histories: keys.reduce(into: [:]) { $0[$1] = metricHistory[$1] ?? [] }
            )
        }
        .sheet(isPresented: $showGauges) {
            let filteredData = pinnedKeys.isEmpty
                ? liveData
                : liveData.filter { pinnedKeys.contains($0.key) }
            GaugeGridView(liveData: filteredData)
        }
    }

    private func toggle(_ key: String) {
        if pinnedKeys.contains(key) {
            pinnedKeys.remove(key)
        } else if pinnedKeys.count < maxPins {
            pinnedKeys.insert(key)
        }
    }
}
