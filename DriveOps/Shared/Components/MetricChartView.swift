//
//  MetricChartView.swift
//  DriveOps
//

import SwiftUI
import Charts

struct MetricChartView: View {
    let label: String
    let value: String
    let history: [MetricSample]
    var isPinned: Bool = false
    var onPin: (() -> Void)? = nil

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(value)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            if history.count > 1 {
                SparklineView(samples: history, tint: Color.accentColor)
                    .frame(height: 32)
            } else {
                Rectangle()
                    .fill(.clear)
                    .frame(height: 32)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            isPinned
                ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isPinned ? Color.accentColor.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.15), value: isPinned)
        .onTapGesture {
            if history.count > 1 { showDetail = true }
        }
        .onLongPressGesture(minimumDuration: 0.2) {
            onPin?()
        }
        .sheet(isPresented: $showDetail) {
            MetricDetailSheet(label: label, history: history)
        }
    }
}

// MARK: - Sparkline

private struct SparklineView: View {
    let samples: [MetricSample]
    var tint: Color = .accentColor

    private var minVal: Double { samples.map(\.value).min() ?? 0 }
    private var maxVal: Double { samples.map(\.value).max() ?? 1 }

    var body: some View {
        Chart(samples) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Value", sample.value)
            )
            .foregroundStyle(tint)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", sample.timestamp),
                yStart: .value("Min", minVal),
                yEnd: .value("Value", sample.value)
            )
            .foregroundStyle(tint.opacity(0.15))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: minVal...(maxVal == minVal ? minVal + 1 : maxVal))
    }
}

// MARK: - Metric metadata

private struct MetricInfo {
    let unit: String
    let description: String
    let normalRange: String

    static let lookup: [String: MetricInfo] = [
        "Engine RPM":               .init(unit: "rpm", description: "Crankshaft rotations per minute. Higher values mean the engine is working harder.", normalRange: "600 – 3 500 rpm"),
        "Vehicle Speed":            .init(unit: "km/h", description: "Current vehicle speed as reported by the ECU.", normalRange: "0 – 130 km/h"),
        "Coolant Temperature":      .init(unit: "°C",  description: "Engine coolant temperature. The engine runs best between 85–95 °C.", normalRange: "85 – 95 °C"),
        "Throttle Position":        .init(unit: "%",   description: "How far the throttle plate is open. 0% is idle, 100% is wide-open throttle.", normalRange: "0 – 100 %"),
        "Engine Load":              .init(unit: "%",   description: "Percentage of maximum torque the engine is currently producing.", normalRange: "15 – 85 %"),
        "Intake Air Temperature":   .init(unit: "°C",  description: "Temperature of air entering the intake manifold. Cooler air improves combustion.", normalRange: "20 – 50 °C"),
        "Mass Air Flow":            .init(unit: "g/s", description: "Grams of air entering the engine per second. Used to calculate fuel delivery.", normalRange: "2 – 200 g/s"),
        "Barometric Pressure":      .init(unit: "kPa", description: "Ambient atmospheric pressure. Affects air density and fuelling.", normalRange: "95 – 105 kPa"),
        "Intake Manifold Pressure": .init(unit: "kPa", description: "Pressure inside the intake manifold. Low at idle (vacuum), higher under load.", normalRange: "30 – 100 kPa"),
        "Timing Advance":           .init(unit: "°",   description: "Degrees before TDC that the spark fires. More advance improves efficiency at light load.", normalRange: "10 – 25 °"),
    ]
}

// MARK: - Detail Sheet

struct MetricDetailSheet: View {
    let label: String
    let history: [MetricSample]

    @Environment(\.dismiss) private var dismiss

    private var info: MetricInfo? { MetricInfo.lookup[label] }
    private var minVal: Double { history.map { $0.value }.min() ?? 0 }
    private var maxVal: Double { history.map { $0.value }.max() ?? 1 }
    private var latest: Double { history.last?.value ?? 0 }
    private var average: Double {
        guard !history.isEmpty else { return 0 }
        return history.reduce(0.0) { $0 + $1.value } / Double(history.count)
    }
    private var gaugeMin: Double { MetricGaugeDomain.min(for: label, observed: minVal) }
    private var gaugeMax: Double { MetricGaugeDomain.max(for: label, observed: maxVal) }
    private var gaugeCurrent: Double {
        Swift.max(gaugeMin, Swift.min(gaugeMax, latest))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Hero gauge — same style as CompareSheet
                    VStack(spacing: 8) {
                        Gauge(value: gaugeCurrent, in: gaugeMin...gaugeMax) {
                            EmptyView()
                        } currentValueLabel: {
                            Text(String(format: "%.1f", latest))
                                .font(.system(.title, design: .rounded).bold())
                        } minimumValueLabel: {
                            Text(String(format: "%.0f", gaugeMin))
                                .font(.caption2).foregroundStyle(.tertiary)
                        } maximumValueLabel: {
                            Text(String(format: "%.0f", gaugeMax))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .gaugeStyle(.accessoryCircular)
                        .scaleEffect(2.0)
                        .frame(height: 120)

                        if let unit = info?.unit {
                            Text(unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                    // Description card
                    if let info {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(info.description)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            HStack {
                                Label("Normal range", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(info.normalRange)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Chart with avg rule
                    Chart(history) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value(label, sample.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            yStart: .value("Min", minVal),
                            yEnd: .value("Value", sample.value)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                        .interpolationMethod(.catmullRom)

                        RuleMark(y: .value("Average", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Color.accentColor.opacity(0.5))
                            .annotation(position: .top, alignment: .leading) {
                                Text("avg")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor.opacity(0.7))
                            }

                        if let last = history.last {
                            PointMark(
                                x: .value("Time", last.timestamp),
                                y: .value(label, last.value)
                            )
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(50)
                        }
                    }
                    .chartYScale(domain: minVal...(maxVal == minVal ? minVal + 1 : maxVal))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .second, count: 30)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.minute().second())
                        }
                    }
                    .frame(height: 280)
                    .padding(.horizontal, 4)

                    // Stats table
                    VStack(spacing: 0) {
                        ForEach([
                            ("Current", String(format: "%.2f", latest)),
                            ("Average", String(format: "%.2f", average)),
                            ("Min",     String(format: "%.2f", minVal)),
                            ("Max",     String(format: "%.2f", maxVal)),
                            ("Samples", "\(history.count)"),
                        ], id: \.0) { row in
                            if row.0 != "Current" { Divider() }
                            HStack {
                                Text(row.0)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(row.1)
                                    .font(.caption.monospacedDigit().bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle(label)
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

