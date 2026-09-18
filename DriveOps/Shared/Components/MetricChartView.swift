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
                Text(value)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if let onPin {
                    Button {
                        onPin()
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
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
        .adaptivePresentation(isPresented: $showDetail) {
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

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isWide: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            Group {
                if isWide {
                    iPadLayout
                } else {
                    ScrollView { phoneLayout }
                }
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

    // MARK: - iPad: fills full screen via GeometryReader
    private var iPadLayout: some View {
        GeometryReader { geo in
            let padding: CGFloat = 20
            let spacing: CGFloat = 16
            let statsH: CGFloat = 200
            let availH = geo.size.height - padding * 2 - spacing - statsH
            let topH = max(availH, 260)

            VStack(spacing: spacing) {
                HStack(alignment: .top, spacing: padding) {
                    VStack(spacing: 16) {
                        gaugeCard(scale: 3.0, frameHeight: min(topH * 0.55, 240))
                        if let info { infoCard(info: info) }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 300)

                    metricChart(height: topH)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: topH)

                statsGrid
                    .frame(height: statsH)
            }
            .padding(padding)
        }
        .ignoresSafeArea(edges: [])
    }

    // MARK: - Phone: stacked
    private var phoneLayout: some View {
        VStack(spacing: 16) {
            gaugeCard(scale: 2.2, frameHeight: 130)
            if let info { infoCard(info: info) }
            metricChart(height: 280)
            statsGrid
        }
        .padding()
    }

    // MARK: - Subviews

    private func gaugeCard(scale: CGFloat, frameHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            Gauge(value: gaugeCurrent, in: gaugeMin...gaugeMax) {
                EmptyView()
            } currentValueLabel: {
                Text(String(format: "%.1f", latest))
                    .font(.system(.title, design: .rounded).bold())
                    .foregroundStyle(Color.accentColor)
            } minimumValueLabel: {
                Text(String(format: "%.0f", gaugeMin))
                    .font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(String(format: "%.0f", gaugeMax))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Color.accentColor)
            .scaleEffect(scale)
            .frame(height: frameHeight)

            if let unit = info?.unit {
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func infoCard(info: MetricInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(info.description)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Label("Normal range", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(info.normalRange)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricChart(height: CGFloat) -> some View {
        Chart(history) { sample in
            LineMark(x: .value("Time", sample.timestamp), y: .value(label, sample.value))
                .foregroundStyle(Color.accentColor).interpolationMethod(.catmullRom)
            AreaMark(x: .value("Time", sample.timestamp), yStart: .value("Min", minVal), yEnd: .value("Value", sample.value))
                .foregroundStyle(Color.accentColor.opacity(0.12)).interpolationMethod(.catmullRom)
            RuleMark(y: .value("Average", average))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(Color.accentColor.opacity(0.5))
                .annotation(position: .top, alignment: .leading) {
                    Text("avg").font(.caption2).foregroundStyle(Color.accentColor.opacity(0.7))
                }
            if let last = history.last {
                PointMark(x: .value("Time", last.timestamp), y: .value(label, last.value))
                    .foregroundStyle(Color.accentColor).symbolSize(50)
            }
        }
        .chartYScale(domain: minVal...(maxVal == minVal ? minVal + 1 : maxVal))
        .chartXAxis {
            AxisMarks(values: .stride(by: .second, count: 30)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.minute().second())
            }
        }
        .frame(height: height)
        .padding(.horizontal, 4)
    }

    private var stdDev: Double {
        guard history.count > 1 else { return 0 }
        let mean = average
        let variance = history.reduce(0.0) { $0 + pow($1.value - mean, 2) } / Double(history.count)
        return sqrt(variance)
    }

    private var trend: String {
        guard history.count >= 6 else { return "—" }
        let recent = history.suffix(6).map { $0.value }
        let older = history.dropLast(6).suffix(6).map { $0.value }
        guard !older.isEmpty else { return "—" }
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        let delta = recentAvg - olderAvg
        let threshold = stdDev * 0.15
        #if os(iOS)
        if delta > threshold { return "↑" }
        if delta < -threshold { return "↓" }
        return "→"
        #else
        if delta > threshold { return "↑ Rising" }
        if delta < -threshold { return "↓ Falling" }
        return "→ Stable"
        #endif
    }

    private var statsGrid: some View {
        let cells: [(String, String, Color)] = [
            ("Current",  String(format: "%.2f", latest),          .accentColor),
            ("Average",  String(format: "%.2f", average),         .primary),
            ("Min",      String(format: "%.2f", minVal),          .primary),
            ("Max",      String(format: "%.2f", maxVal),          .primary),
            ("Range",    String(format: "%.2f", maxVal - minVal), .primary),
            ("Std Dev",  String(format: "%.2f", stdDev),          .primary),
            ("Trend",    trend,                                    trendColor),
            ("Samples",  "\(history.count)",                      .secondary),
        ]
        let columns = [GridItem(.flexible()), GridItem(.flexible()),
                       GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(cells, id: \.0) { label, val, color in
                VStack(spacing: 4) {
                    Text(val)
                        .font(.system(.title3, design: .rounded).bold().monospacedDigit())
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var trendColor: Color {
        if trend.contains("↑") { return .green }
        if trend.contains("↓") { return .orange }
        return .secondary
    }
}

