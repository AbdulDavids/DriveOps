# Architecture overview

DriveOps is a SwiftUI app that connects to OBD-II vehicle adapters over Bluetooth or Wi-Fi, reads live sensor data, and displays it in real time. It also reads and clears diagnostic trouble codes (DTCs) from the vehicle's ECU.

## Structure

```
DriveOps/
├── DriveOpsApp.swift              App entry point
├── ContentView.swift               Root coordinator — owns TabView, sheet state, WiFiHelper
├── OBDViewModel.swift               Single shared ViewModel for all features
│
├── Core/
│   └── Services/
│       ├── OBDServiceProtocol.swift   Placeholder for a testable abstraction (not yet used)
│       └── DrivingSimulator.swift     Demo mode's data source — a self-contained driving cycle
│
├── Features/
│   ├── Dashboard/
│   │   ├── DashboardView.swift        Tab 1 — connection card, vehicle info, live data, gauges
│   │   └── DashboardViewModel.swift   OBDViewModel extension: statusColor, statusLabel
│   ├── Diagnostics/
│   │   ├── DiagnosticsView.swift      Tab 2 — DTC list, search, scan/clear
│   │   ├── DiagnosticsViewModel.swift OBDViewModel extension: scan/clear trouble codes
│   │   └── TroubleCodeDetailView.swift  Code detail + AI explanation
│   ├── Logs/
│   │   └── LogsView.swift             Tab 3 — timestamped activity log
│   ├── Onboarding/
│   │   └── WelcomeFlowView.swift      First-run walkthrough
│   └── Settings/
│       └── SettingsView.swift         Tab 4 — app version, demo mode, AI provider, changelog
│
├── Shared/
│   └── Components/
│       ├── ConnectionCardView.swift   BT/WiFi connect buttons, cancel, disconnect
│       ├── BluetoothInfoSheet.swift   Sheet with BT setup steps + connect button
│       ├── WiFiInfoSheet.swift        Sheet with WiFi setup steps + connect button
│       ├── VehicleInfoCardView.swift  Protocol, VIN, supported PIDs
│       ├── LiveDataCardView.swift     Sorted live sensor readings
│       ├── MetricChartView.swift      Per-metric history chart
│       ├── CompareSheet.swift         Two-metric comparison view
│       ├── GaugeGridView.swift        iPad gauge grid layout
│       └── InfoRow.swift              Reusable label/value row
│
├── Models/
│   ├── MetricSample.swift             Timestamped value used for history/charts
│   └── AIChatProvider.swift           ChatGPT/Claude/Gemini/Mistral deep-link URLs
│
└── Utilities/
    ├── WiFiHelper.swift               SSID detection (currently disabled — needs entitlement)
    └── AppLogger.swift                os.Logger categories mirroring the in-app Logs tab
```

## Connection types

The app has three connection modes, layered over the OBD2 library's own `ConnectionType` (`AppConnectionType` in `OBDViewModel.swift`):

| Mode      | Transport         | Backed by `OBDService`? | Notes                                   |
|-----------|--------------------|--------------------------|------------------------------------------|
| Bluetooth | BLEManager          | Yes                      | Persistent `bluetoothService` instance   |
| Wi-Fi     | WifiManager          | Yes                      | New `OBDService` instance per connection |
| Demo      | `DrivingSimulator`   | No                       | Runs entirely in the app, never touches the OBD2 library |

The OBD2 library (EVMSwiftOBD2, a fork of SwiftOBD2 — see the [README](../../README.md#how-it-works)) only ships mock data behind `#if targetEnvironment(simulator)`, with no way to request it at runtime on a real device. That's why demo mode is implemented as a separate code path in the app instead of a library connection type: it needs to work identically on a physical iPhone with no adapter plugged in.

## Tabs

1. **Dashboard** — connection card, vehicle info, live sensor readings, gauges, metric history/comparison
2. **Diagnostics** — DTC list with search, scan and clear
3. **Logs** — timestamped activity log (connection attempts, poll cycles, errors)
4. **Settings** — app version, demo mode toggle, AI chat provider picker, changelog

See [connection lifecycle](connection-lifecycle.md) and [data flow](data-flow.md) for how these fit together.
