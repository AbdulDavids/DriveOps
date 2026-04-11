# DriveOps Architecture

## Overview

DriveOps is a SwiftUI app that connects to OBD-II vehicle adapters over Bluetooth or Wi-Fi, reads live sensor data, and displays it in real time.

## Structure

```
DriveOps/
├── DriveOpsApp.swift           # App entry point
├── ContentView.swift           # Root coordinator — owns TabView, sheet state, WiFiHelper
├── OBDViewModel.swift          # Single shared ViewModel for all features
│
├── Core/
│   └── Services/
│       └── OBDServiceProtocol.swift   # Placeholder for testable abstraction (not yet used)
│
├── Features/
│   ├── Dashboard/
│   │   ├── DashboardView.swift        # Tab 1 — connection card + vehicle info + live data
│   │   └── DashboardViewModel.swift   # OBDViewModel extension: statusColor, statusLabel
│   ├── Logs/
│   │   └── LogsView.swift             # Tab 2 — timestamped activity log
│   └── Settings/
│       └── SettingsView.swift         # Tab 3 — app version, demo mode
│
├── Shared/
│   └── Components/
│       ├── ConnectionCardView.swift   # BT/WiFi connect buttons, cancel, disconnect
│       ├── BluetoothInfoSheet.swift   # Sheet with BT setup steps + connect button
│       ├── WiFiInfoSheet.swift        # Sheet with WiFi setup steps + connect button
│       ├── VehicleInfoCardView.swift  # Protocol, VIN, supported PIDs
│       ├── LiveDataCardView.swift     # Sorted live sensor readings
│       ├── InfoRow.swift              # Reusable label/value row
│       └── (placeholder for more)
│
└── Utilities/
    └── WiFiHelper.swift               # SSID detection (currently disabled — needs entitlement)
```

## Data Flow

```
OBDService (SwiftOBD2)
    │
    │  $connectionState (Combine publisher)
    ▼
OBDViewModel  ──────────────────────────────────────────────────┐
  @Published connectionState                                     │
  @Published obdInfo                                             │
  @Published liveData [String: String]                           │
  @Published isConnecting                                        │
  @Published activeConnectionType                                │
  @Published logs                                                │
    │                                                            │
    ▼                                                            ▼
ContentView (root)                                     All feature views
  owns: WiFiHelper                                     observe via @ObservedObject
  owns: showBTSheet, showWifiSheet state
```

## Connection Types

There are three connection modes, all backed by `OBDService` from SwiftOBD2:

| Mode      | Transport       | Notes                                      |
|-----------|-----------------|--------------------------------------------|
| Bluetooth | BLEManager      | Persistent `bluetoothService` instance     |
| Wi-Fi     | WifiManager     | New `OBDService` instance per connection   |
| Demo      | MOCKComm        | New `OBDService` instance per connection   |

**Important:** In the iOS Simulator, SwiftOBD2 forces `MOCKComm` for all connection types (`#if targetEnvironment(simulator)`). BT and WiFi will only use real hardware on a physical device.

## OBDViewModel Connection Lifecycle

1. User taps BT or WiFi button → sheet opens
2. User taps Connect in sheet → `connect()` or `connectWifi()` called
3. `startConnecting(type:service:)` is called:
   - Sets `isConnecting = true`, `activeConnectionType`
   - Calls `bind(_:)` — subscribes `$connectionState` from the new service
   - Stores `connectTask` so it can be cancelled
4. On success: `startLiveDataWith(_:)` begins polling loop (300ms interval)
5. Cancel: `cancelConnection()` kills `connectTask`, stops service, resets state
6. Disconnect: `disconnect()` cancels poll task, stops `activeService`, clears all state

## Live Data Polling

Polls 10 PIDs every 300ms via `service.requestPIDs(_:unit:)`:
- RPM, Speed, Coolant Temp, Throttle Position, Engine Load
- Intake Air Temp, MAF, Barometric Pressure, Intake Manifold Pressure, Timing Advance

**Excluded PIDs (SwiftOBD2 bugs):**
- `.fuelLevel` — crashes: `String(format:)` receives `Double` for `%02X` specifier
- `.controlModuleVoltage` — no mock response, returns "No Data"

See `/swiftobd2-bug-report.md` for full details and the upstream PR plan.

## Known Limitations

- WiFiHelper SSID detection is disabled — requires the "Access WiFi Information" entitlement, which needs a paid Apple Developer account
- No unit tests yet — `OBDViewModel.stub()` and `OBDServiceProtocol` are scaffolded for when tests are added
