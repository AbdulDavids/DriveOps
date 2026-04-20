//
//  GaugeGridView.swift
//  DriveOps
//

import SwiftUI

struct GaugeGridView: View {
    let liveData: [String: String]

    @Environment(\.dismiss) private var dismiss

    private let colors: [Color] = [.accentColor, .orange, .green, .pink, .purple, .cyan, .mint, .red, .indigo, .yellow]

    private var sorted: [(key: String, value: String)] {
        liveData.sorted { $0.key < $1.key }
    }

    private func parsed(_ value: String) -> Double {
        Double(value.components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted).joined()) ?? 0
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                let cols = isLandscape ? sorted.count : 1
                let rows = isLandscape ? 1 : sorted.count
                let spacing: CGFloat = 12
                let hPad: CGFloat = 16
                let vPad: CGFloat = 16
                let availW = geo.size.width - hPad * 2 - spacing * CGFloat(cols - 1)
                let availH = geo.size.height - vPad * 2 - spacing * CGFloat(rows - 1)
                let cellW = availW / CGFloat(cols)
                let cellH = availH / CGFloat(rows)

                let columns = Array(repeating: GridItem(.fixed(cellW), spacing: spacing), count: cols)

                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(Array(sorted.enumerated()), id: \.element.key) { index, item in
                        let current = parsed(item.value)
                        let gMin = MetricGaugeDomain.min(for: item.key, observed: current)
                        let gMax = MetricGaugeDomain.max(for: item.key, observed: current)
                        BigGaugeCell(
                            label: item.key,
                            current: current,
                            gaugeMin: gMin,
                            gaugeMax: gMax,
                            cellHeight: cellH,
                            color: colors[index % colors.count]
                        )
                        .frame(width: cellW, height: cellH)
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
            }
            .navigationTitle("Gauges")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct BigGaugeCell: View {
    let label: String
    let current: Double
    let gaugeMin: Double
    let gaugeMax: Double
    let cellHeight: CGFloat

    let color: Color

    private var clamped: Double { Swift.max(gaugeMin, Swift.min(gaugeMax, current)) }
    private var gaugeScale: CGFloat { max(1.0, min(3.0, cellHeight / 120)) }

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Gauge(value: clamped, in: gaugeMin...gaugeMax) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.1f", current))
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(color)
            } minimumValueLabel: {
                Text(String(format: "%.0f", gaugeMin))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(String(format: "%.0f", gaugeMax))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color)
            .scaleEffect(gaugeScale)
            .frame(width: 60 * gaugeScale, height: 60 * gaugeScale)

            Spacer()

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
