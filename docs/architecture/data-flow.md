# Data flow

```
OBDService (EVMSwiftOBD2)
    │
    │  $connectionState (Combine publisher)
    │  onLog / onAdapterInfoUpdated (callbacks)
    ▼
OBDViewModel ──────────────────────────────────────────────┐
  @Published connectionState                                │
  @Published obdInfo                                         │
  @Published liveData        [String: String]                │
  @Published metricHistory   [String: [MetricSample]]         │
  @Published activeConnectionType (AppConnectionType)          │
  @Published troubleCodes    [ECUID: [TroubleCode]]             │
  @Published logs            [String]                           │
    │                                                          │
    ▼                                                          ▼
ContentView (root)                                    All feature views
  owns: WiFiHelper                                    observe via @ObservedObject
  owns: showBTSheet, showWifiSheet state
```

`OBDViewModel` is the single shared source of truth for the whole app — every tab observes the same instance rather than each feature owning its own state. See [decisions.md](../decisions.md#why-a-single-obdviewmodel-for-all-tabs) for why.

## Logging

`OBDViewModel.log(_:)` does two things on every call:
1. Appends a timestamped line to `@Published var logs`, capped at 500 entries, which the Logs tab renders directly.
2. Mirrors the message to `AppLogger.connection` (an `os.Logger`), so the same activity is visible in Console.app or Xcode's debug console without opening the app's Logs tab.

Higher-volume or more structured detail (per-poll-cycle timing, per-PID counts) goes only to the system log via the category-specific loggers in `AppLogger.swift` (`.liveData`, `.diagnostics`, `.demo`), since logging every 300ms poll to the in-app array would flood it during a long drive. The in-app log gets a periodic summary instead (every 50 cycles).

## Metric history

`metricHistory` is a `[String: [MetricSample]]` keyed by the same human-readable description used in `liveData` (e.g. `"Engine RPM"`). Each sample is `(timestamp, value)`. This is what feeds the per-metric chart (`MetricChartView`), the compare sheet, and the gauge grid — all three read from the same history rather than maintaining their own.
