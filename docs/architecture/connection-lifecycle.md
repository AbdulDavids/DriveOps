# Connection lifecycle

All connection state lives in `OBDViewModel`. This is what happens from tapping a connect button to seeing live data.

## Connect

1. User taps **Bluetooth** or **Wi-Fi** on the connection card → the matching info sheet opens.
2. Bluetooth: user taps **Connect** in `BluetoothInfoSheet` → `BLEDevicePickerSheet` opens on top of it and calls `vm.startPeripheralScan()`.
   Wi-Fi: `connectWifi()` runs directly (no picker — Wi-Fi has no device-discovery step).
3. `startPeripheralScan()` runs an **unfiltered** BLE scan (`OBDService.scanForPeripherals()`, no service UUID filter) so every nearby peripheral shows up, not only ones the library already recognises by service UUID. Results stream into `discoveredPeripherals` via `onPeripheralsUpdated`.
4. User taps a device in the list → `vm.connect(to: peripheral)` stops the scan and calls `startConnecting(type:service:peripheral:)` with that specific `CBPeripheral`, then the picker dismisses itself. `BluetoothInfoSheet`'s `onDismiss` closes itself too once `isConnecting` is true, so only the connection card is left showing progress.
5. `startConnecting(type:service:peripheral:)`:
   - Sets `isConnecting = true` and `activeConnectionType`
   - Calls `bind(_:)`, which subscribes to the service's `$connectionState` and wires up `onLog`/`onAdapterInfoUpdated` so the library's own internal logging shows up in the app's Logs tab
   - Stores `connectTask` so the attempt can be cancelled
   - Passes `peripheral` straight through to `OBDService.startConnection(peripheral:)`, skipping the library's own scan-and-take-first behavior
6. On success: `startLiveDataWith(_:)` begins the polling loop (300ms interval). The log line includes elapsed connect time, detected protocol, VIN, PID count, and ECU count.
7. On failure: `errorMessage` is set, `activeConnectionType` clears, and the failure (with elapsed time) is logged.

`connect()` (no peripheral) still exists and falls back to the library's own scan-and-take-first behavior — used by demo/preview code, not by the picker flow.

Demo mode follows a separate path: `connectDemo()` → `startConnectingDemo()` sets `activeConnectionType = .demo`, waits ~400ms to feel like a real connection attempt, then goes straight to `connectionState = .connectedToVehicle` and starts `startSimulatedPoll()`. No `OBDService` is created or touched — see [overview.md](overview.md#connection-types) for why.

### Why a device picker instead of connecting to the first BLE peripheral found?

The library's own `connectAsync` scans and grabs whichever compatible peripheral answers first. That breaks as soon as more than one BLE OBD2 adapter is in range (a neighbour's car, a second dongle on the seat) — the app could connect to the wrong one with no way for the user to intervene. `BLEDevicePickerSheet` shows every discovered peripheral and lets the user choose, mirroring how vendor apps (e.g. YMOBD) present a "Nearby equipment" list.

The scan is also intentionally **unfiltered**. The library's default scan only surfaces peripherals advertising one of three known service UUIDs (`FFE0`/`FFF0`/`18F0`); several clones advertise a bare name and only reveal their GATT services after connecting. Filtering at scan time would hide those from the picker entirely. The fork DriveOps currently depends on (`AbdulDavids/EVMSwiftOBD2`, see `/swiftobd2-bug-report.md`) also discovers all of a connected peripheral's services and falls back to classifying characteristics by read/write/notify properties when no known UUID matches — so an adapter that shows up in the picker has a real chance of working even if its GATT layout has never been catalogued.

## Cancel

`cancelConnection()` — used while `isConnecting` is still true (user backs out mid-attempt):
- Cancels `connectTask`
- Stops and clears `activeService` (a no-op in demo mode, since there's no service)
- Resets `isConnecting`, `activeConnectionType`, `connectionState`, `metricHistory`

## Disconnect

`disconnect()` — used once connected:
- Cancels `pollTask`
- Stops and clears `activeService`
- Resets `connectionState`, `activeConnectionType`, `obdInfo`, `liveData`, `metricHistory`
- Logs a session summary: poll cycle count and error count, then resets those counters

## Live data polling

Polls `vm.selectedPIDs` every 300ms via `service.requestPIDs(_:unit:)`, re-reading the set fresh each cycle rather than snapshotting it once — so a change in the PID picker (Settings → Live Data PIDs) takes effect on the very next tick without a reconnect. See [decisions.md](../decisions.md#why-is-the-live-data-poll-list-user-selectable-instead-of-fixed) for why this replaced a fixed 10-PID list, and `Models/PIDSelection.swift` for the catalog (every mode-1 PID with `CommandProperties.live == true`) and persistence.

Each cycle:
- Skips the request entirely if `selectedPIDs` is momentarily empty (only reachable transiently while the picker is mid-edit) rather than sending a pointless zero-PID query
- Updates `liveData` (formatted strings) and appends to `metricHistory` (raw values, capped at 120 samples per metric)
- Counts cycles and errors for the session
- Logs a summary to the in-app Logs tab every 50 cycles; every cycle goes to the system log (`AppLogger.liveData`) at debug level
- Flags partial batches (fewer results than PIDs requested) and empty batches, not just outright failures

`OBDService.requestPIDs` (in the `AbdulDavids/EVMSwiftOBD2` fork DriveOps depends on) chunks the PID list into requests of at most 6 — a mode-01 query with more PIDs than that in one go got a flat "NO DATA" from a real vehicle in testing, per SAE J1979's per-request limit under CAN framing. This matters more now that PID selection is open-ended rather than a fixed count.

Demo mode's polling loop (`startSimulatedPoll()`) is structurally the same but pulls from `DrivingSimulator.tick()` instead of the network, and never fails — there's no transport to report errors from. It's unaffected by the PID picker: its metric set is fixed, independent of `OBDCommand`.

## Diagnostics (DTCs)

`scanTroubleCodes()` and `clearTroubleCodes()` live in `DiagnosticsViewModel.swift` (an `OBDViewModel` extension). Demo mode returns a static fixture (`demoDTCs`) after a simulated delay instead of calling the service. Both operations log start, completion (with counts and elapsed time), and failure.
