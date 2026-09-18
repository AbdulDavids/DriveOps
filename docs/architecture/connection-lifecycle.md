# Connection lifecycle

All connection state lives in `OBDViewModel`. This is what happens from tapping a connect button to seeing live data.

## Connect

1. User taps **Bluetooth** or **Wi-Fi** on the connection card → the matching info sheet opens.
2. User taps **Connect** in the sheet → `connect()` or `connectWifi()` runs.
3. `startConnecting(type:service:)`:
   - Sets `isConnecting = true` and `activeConnectionType`
   - Calls `bind(_:)`, which subscribes to the service's `$connectionState` and wires up `onLog`/`onAdapterInfoUpdated` so the library's own internal logging shows up in the app's Logs tab
   - Stores `connectTask` so the attempt can be cancelled
4. On success: `startLiveDataWith(_:)` begins the polling loop (300ms interval). The log line includes elapsed connect time, detected protocol, VIN, PID count, and ECU count.
5. On failure: `errorMessage` is set, `activeConnectionType` clears, and the failure (with elapsed time) is logged.

Demo mode follows a separate path: `connectDemo()` → `startConnectingDemo()` sets `activeConnectionType = .demo`, waits ~400ms to feel like a real connection attempt, then goes straight to `connectionState = .connectedToVehicle` and starts `startSimulatedPoll()`. No `OBDService` is created or touched — see [overview.md](overview.md#connection-types) for why.

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

Polls 10 PIDs every 300ms via `service.requestPIDs(_:unit:)`:

RPM, speed, coolant temperature, throttle position, engine load, intake air temperature, MAF, barometric pressure, intake manifold pressure, timing advance.

Each cycle:
- Updates `liveData` (formatted strings) and appends to `metricHistory` (raw values, capped at 120 samples per metric)
- Counts cycles and errors for the session
- Logs a summary to the in-app Logs tab every 50 cycles; every cycle goes to the system log (`AppLogger.liveData`) at debug level
- Flags partial batches (fewer results than PIDs requested) and empty batches, not just outright failures

**Excluded PIDs (upstream bugs):**
- `.fuelLevel` — crashes: `String(format:)` receives a `Double` for a `%02X` specifier
- `.controlModuleVoltage` — no mock response, returns "No Data"

Both bugs are present in EVMSwiftOBD2 too (inherited from SwiftOBD2). See `/swiftobd2-bug-report.md` at the repo root for detail and the fix plan.

Demo mode's polling loop (`startSimulatedPoll()`) is structurally the same but pulls from `DrivingSimulator.tick()` instead of the network, and never fails — there's no transport to report errors from.

## Diagnostics (DTCs)

`scanTroubleCodes()` and `clearTroubleCodes()` live in `DiagnosticsViewModel.swift` (an `OBDViewModel` extension). Demo mode returns a static fixture (`demoDTCs`) after a simulated delay instead of calling the service. Both operations log start, completion (with counts and elapsed time), and failure.
