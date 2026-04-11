# Design Decisions

## Why a single OBDViewModel for all tabs?

The connection state, live data, and logs are all global to the session — not scoped to any one tab. Splitting into per-feature ViewModels would require either prop-drilling the shared state or introducing a coordinator/environment object. A single VM keeps it simple for the current scope.

## Why does ContentView own sheet state instead of DashboardView?

The BT and WiFi sheets (`showBTSheet`, `showWifiSheet`) are presented at the root `TabView` level via `.sheet(isPresented:)`. If they were owned by `DashboardView`, switching tabs while a sheet is open could cause dismissal issues. Root ownership keeps presentation stable.

## Why activeService instead of always using bluetoothService?

WiFi and Demo connections create a new `OBDService` instance each time. `disconnect()` needs to stop whichever service is actually active. `activeService` tracks this so we never accidentally stop the wrong service or leave a connection open.

## Why no OBDServiceProtocol conformance yet?

`OBDService` is a third-party class with `@Published private(set)` properties and async methods with default parameters. Retroactive protocol conformance from the app target hit Swift concurrency and module boundary issues. The protocol stub exists in `Core/Services/` as a placeholder — wire it up when unit tests are added and you control a mock implementation.

## Why are .fuelLevel and .controlModuleVoltage excluded from polling?

Both are bugs in the upstream SwiftOBD2 library:
- `.fuelLevel`: crashes the process — `String(format: "%02X", someDouble)` is a type mismatch
- `.controlModuleVoltage`: silently returns no data in demo mode

A PR to fix both is tracked in `/swiftobd2-bug-report.md`.

## Connection button UX

Buttons open an info sheet rather than connecting directly. This gives the user context (setup steps, open Settings shortcut) before committing to a connection attempt, and avoids a confusing immediate spinner with no explanation.

## Simulator warning

A small warning is shown in the connection card when running in the simulator, since SwiftOBD2 hardcodes `MOCKComm` for all connection types in that environment. This prevents confusion when BT/WiFi appear to "connect" instantly with mock data.
