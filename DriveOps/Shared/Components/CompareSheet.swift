//
//  CompareSheet.swift
//  DriveOps
//

import SwiftUI
import Charts

struct CompareSheet: View {
    let keys: [String]
    let histories: [String: [MetricSample]]

    @Environment(\.dismiss) private var dismiss

    private let seriesColors: [Color] = [.accentColor, .orange, .green, .pink]

    private struct NormalisedPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let normValue: Double
        let series: String
    }

    private var points: [NormalisedPoint] {
        keys.flatMap { normalise(histories[$0] ?? [], label: $0) }
    }

    private func normalise(_ samples: [MetricSample], label: String) -> [NormalisedPoint] {
        guard !samples.isEmpty else { return [] }
        let vals = samples.map(\.value)
        let lo = vals.min()!
        let hi = vals.max()!
        let range = hi - lo
        return samples.map { s in
            NormalisedPoint(
                timestamp: s.timestamp,
                normValue: range == 0 ? 0.5 : (s.value - lo) / range,
                series: label
            )
        }
    }

    private func stats(_ key: String) -> (min: Double, max: Double, current: Double) {
        let samples = histories[key] ?? []
        let vals = samples.map { $0.value }
        return (vals.min() ?? 0, vals.max() ?? 0, samples.last?.value ?? 0)
    }

    private func color(for key: String) -> Color {
        seriesColors[(keys.firstIndex(of: key) ?? 0) % seriesColors.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Circular gauges
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: min(keys.count, 4))
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(keys, id: \.self) { key in
                            let s = stats(key)
                            let gMin = MetricGaugeDomain.min(for: key, observed: s.min)
                            let gMax = MetricGaugeDomain.max(for: key, observed: s.max)
                            MetricGaugeCell(
                                label: key,
                                current: s.current,
                                gaugeMin: gMin,
                                gaugeMax: gMax,
                                color: color(for: key)
                            )
                        }
                    }

                    // Overlaid chart
                    Chart(points) { pt in
                        LineMark(
                            x: .value("Time", pt.timestamp),
                            y: .value("Value", pt.normValue)
                        )
                        .foregroundStyle(by: .value("Metric", pt.series))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartForegroundStyleScale(
                        domain: keys,
                        range: keys.map { color(for: $0) }
                    )
                    .chartLegend(position: .top, alignment: .leading)
                    .chartYAxis {
                        AxisMarks(values: [0.0, 0.5, 1.0]) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let d = val.as(Double.self) {
                                    Text(d == 0 ? "Low" : d == 1 ? "High" : "Mid")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .second, count: 30)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.minute().second())
                        }
                    }
                    .frame(height: 300)
                    .padding(.horizontal, 4)

                    // Stats table
                    VStack(spacing: 0) {
                        HStack {
                            Text("")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(keys, id: \.self) { key in
                                Text(key)
                                    .font(.caption.bold())
                                    .foregroundStyle(color(for: key))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        ForEach(["Current", "Min", "Max"], id: \.self) { stat in
                            Divider()
                            HStack {
                                Text(stat)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                ForEach(keys, id: \.self) { key in
                                    let s = stats(key)
                                    let val = stat == "Current" ? s.current : stat == "Min" ? s.min : s.max
                                    Text(String(format: "%.1f", val))
                                        .font(.caption.monospacedDigit())
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Compare")
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

// MARK: - Shared gauge domain lookup

enum MetricGaugeDomain {
    private static let ranges: [String: (Double, Double)] = [
        "Engine RPM":               (0,   8000),
        "Vehicle Speed":            (0,   220),
        "Coolant Temperature":      (0,   120),
        "Throttle Position":        (0,   100),
        "Engine Load":              (0,   100),
        "Intake Air Temperature":   (0,   80),
        "Mass Air Flow":            (0,   300),
        "Barometric Pressure":      (80,  110),
        "Intake Manifold Pressure": (20,  105),
        "Timing Advance":           (-10, 40),
    ]
    static func min(for key: String, observed: Double) -> Double { ranges[key]?.0 ?? observed }
    static func max(for key: String, observed: Double) -> Double { ranges[key]?.1 ?? (observed + 1) }
}

// MARK: - Gauge Cell

struct MetricGaugeCell: View {
    let label: String
    let current: Double
    let gaugeMin: Double
    let gaugeMax: Double
    let color: Color
    var scale: CGFloat = 1.3

    private var clamped: Double { Swift.max(gaugeMin, Swift.min(gaugeMax, current)) }

    var body: some View {
        VStack(spacing: 8) {
            Gauge(value: clamped, in: gaugeMin...gaugeMax) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.1f", current))
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(color)
            } minimumValueLabel: {
                Text(String(format: "%.0f", gaugeMin))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text(String(format: "%.0f", gaugeMax))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color)
            .scaleEffect(scale)
            .frame(width: 80 * scale, height: 80 * scale)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
