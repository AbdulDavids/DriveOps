//
//  CoDriverLiveActivity.swift
//  CoDriver
//
//  Renders the state LiveActivityController pushes via
//  Activity<CoDriverAttributes> (see DriveOps/LiveActivity/LiveActivityController.swift).
//  Metrics shown are user-picked in Settings (LiveActivityMetricsStore),
//  defaulting to just Engine RPM — so the layout must hold up with anywhere
//  from 1 to 3 metrics, not a fixed speed+RPM pair.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct CoDriverLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoDriverAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.yellow)
        } dynamicIsland: { context in
            DynamicIsland {
                // A single wide bottom region (rather than split
                // leading/trailing slots) so it holds up whether 1 or 3
                // metrics are selected, without the label text getting
                // clipped by the island's narrower side slots.
                DynamicIslandExpandedRegion(.bottom) {
                    metricsRow(context.state.metrics)
                }
            } compactLeading: {
                Image(systemName: "gauge.with.needle.fill")
                    .foregroundStyle(.yellow)
            } compactTrailing: {
                Text(context.state.metrics.first?.formattedValue ?? "—")
                    .font(.system(.caption, design: .monospaced)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: "gauge.with.needle.fill")
                    .foregroundStyle(.yellow)
            }
            .keylineTint(Color.yellow)
        }
    }

    private func metricsRow(_ metrics: [CoDriverAttributes.MetricReading]) -> some View {
        // Below title3 for 3 metrics side by side — a fixed-width column at
        // title3 with lineLimit(1) truncates to an ellipsis before
        // minimumScaleFactor gets a chance to shrink it (seen with values
        // like "1100" clipping to "1 100…").
        let valueFont: Font.TextStyle = metrics.count >= 3 ? .footnote : .title3
        return HStack(spacing: metrics.count >= 3 ? 6 : 12) {
            ForEach(metrics, id: \.label) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.gray)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(metric.formattedValue)
                        .font(.system(valueFont, design: .monospaced).bold())
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: CoDriverAttributes.ContentState

    // Below title2 once lap info shares the row with 2+ metrics — a
    // fixed-width column at title2 with lineLimit(1) truncates to an
    // ellipsis before minimumScaleFactor gets a chance to shrink it (seen
    // with values like "1100" clipping to "1 100…").
    private var valueFont: Font.TextStyle { state.metrics.count >= 2 ? .title3 : .title2 }

    var body: some View {
        HStack(spacing: state.metrics.count >= 2 ? 10 : 16) {
            ForEach(Array(state.metrics.enumerated()), id: \.offset) { index, metric in
                if index > 0 {
                    Divider().overlay(Color.gray.opacity(0.4))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.gray)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(metric.formattedValue)
                        .font(.system(valueFont, design: .monospaced).bold())
                        .monospacedDigit().foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.isLapRunning ? "LAP \(state.lapCount + 1)" : "\(state.lapCount) LAPS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.yellow)
                Text("BEST \(formattedLap(state.bestLapSeconds))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.gray)
            }
        }
        .padding(16)
    }

    private func formattedLap(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—:—.—" }
        let hundredths = Int(seconds * 100)
        return String(format: "%d:%02d.%02d", hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }
}

extension CoDriverAttributes {
    fileprivate static var preview: CoDriverAttributes { CoDriverAttributes(startedAt: .now) }
}

extension CoDriverAttributes.ContentState {
    fileprivate static var driving: CoDriverAttributes.ContentState {
        .init(
            metrics: [
                .init(label: "SPEED", formattedValue: "87 km/h"),
                .init(label: "RPM", formattedValue: "2450"),
            ],
            isConnected: true, lapCount: 2, lastLapSeconds: 92.4, bestLapSeconds: 88.1, isLapRunning: true
        )
    }
    fileprivate static var idle: CoDriverAttributes.ContentState {
        .init(
            metrics: [.init(label: "RPM", formattedValue: "780")],
            isConnected: true, lapCount: 0, lastLapSeconds: nil, bestLapSeconds: nil, isLapRunning: false
        )
    }
    /// Regression case: 3 metrics including a wide 4-digit RPM value used to
    /// clip to "1 100…" — see LiveActivityController.compactFormat/shortLabel.
    fileprivate static var threeMetrics: CoDriverAttributes.ContentState {
        .init(
            metrics: [
                .init(label: "MANIFOLD", formattedValue: "43 kPa"),
                .init(label: "RPM", formattedValue: "1100"),
                .init(label: "SPEED", formattedValue: "9 km/h"),
            ],
            isConnected: true, lapCount: 0, lastLapSeconds: nil, bestLapSeconds: nil, isLapRunning: false
        )
    }
}

#Preview("Notification", as: .content, using: CoDriverAttributes.preview) {
    CoDriverLiveActivity()
} contentStates: {
    CoDriverAttributes.ContentState.driving
    CoDriverAttributes.ContentState.idle
    CoDriverAttributes.ContentState.threeMetrics
}
