# Design decisions

## Why a single OBDViewModel for all tabs?

Connection state, live data, and logs are all global to the session, not scoped to any one tab. Splitting into per-feature ViewModels would mean either prop-drilling the shared state or introducing a coordinator/environment object. A single VM keeps it simple for the current scope.

## Why does ContentView own sheet state instead of DashboardView?

The BT and WiFi sheets (`showBTSheet`, `showWifiSheet`) are presented at the root `TabView` level via `.sheet(isPresented:)`. If `DashboardView` owned them, switching tabs while a sheet is open could cause dismissal issues. Root ownership keeps presentation stable.

## Why activeService instead of always using bluetoothService?

Wi-Fi connections create a new `OBDService` instance each time. `disconnect()` needs to stop whichever service is actually active. `activeService` tracks this so the app never accidentally stops the wrong service or leaves a connection open. Demo mode has no `activeService` at all — see the next entry.

## Why does demo mode not use OBDService?

The original plan (and the old SwiftOBD2 library) supported a `.demo` `ConnectionType` that constructed an `OBDService` wired to mock data. EVMSwiftOBD2 dropped that: mock data (`MOCKComm`) only activates behind `#if targetEnvironment(simulator)`, with no runtime-selectable connection type to request it on a physical device.

Since DriveOps's demo mode needs to work on a real iPhone with no adapter (that's the point of a demo mode), it now runs entirely on the app's own `DrivingSimulator`, feeding the same `liveData`/`metricHistory` published properties the real adapter path uses. `AppConnectionType` (defined in `OBDViewModel.swift`) is the app's own enum layered over the library's `ConnectionType`, adding `.demo` alongside `.bluetooth`/`.wifi`.

## Why fork to EVMSwiftOBD2?

The original dependency, `kkonteh97/SwiftOBD2`, looked unmaintained. `valexa/EVMSwiftOBD2` (tracking its `develop` branch) is a fork with the same public API and module name (`OBDService`, `ConnectionState`, `OBDCommand`, `TroubleCode`, `ECUID`), so the swap required minimal code changes beyond the demo-mode rework above. It's less battle-tested than the original, so DriveOps may end up forking it again to fix issues directly rather than waiting on upstream — see `/swiftobd2-bug-report.md` at the repo root.

## Why no OBDServiceProtocol conformance yet?

`OBDService` is a third-party class with `@Published private(set)` properties and async methods with default parameters. Retroactive protocol conformance from the app target hit Swift concurrency and module boundary issues. The protocol stub exists in `Core/Services/` as a placeholder for when unit tests are added and a mock implementation is needed.

## Why are .fuelLevel and .controlModuleVoltage excluded from polling?

Both are bugs in the OBD2 library's mock data manager, present in both SwiftOBD2 and its EVMSwiftOBD2 fork (same inherited code):
- `.fuelLevel`: crashes the process — `String(format: "%02X", someDouble)` is a type mismatch
- `.controlModuleVoltage`: silently returns no data in mock/demo mode

See `/swiftobd2-bug-report.md` for detail and the fix plan.

## Why mirror logs to os.Logger instead of only the in-app Logs tab?

The in-app `logs` array is only visible while the app is running and attached to a view. Once debugging moves to a real adapter on a real device — where you're not always watching the Logs tab, or the app isn't foregrounded — `os.Logger` output in Console.app or Xcode's console is the only way to see what happened. `AppLogger.swift` gives each subsystem area (connection, live data, diagnostics, demo) its own category so the system log can be filtered without wading through everything.

## Connection button UX

Buttons open an info sheet rather than connecting directly. This gives the user context (setup steps, an Open Settings shortcut) before committing to a connection attempt, and avoids a confusing immediate spinner with no explanation.

## Simulator warning

A small warning is shown in the connection card when running in the iOS Simulator, since the OBD2 library hardcodes mock data for Bluetooth and Wi-Fi in that environment. This prevents confusion when BT/Wi-Fi appear to "connect" instantly with mock data instead of asking for a real adapter.
