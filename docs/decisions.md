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

## Why is the live-data poll list user-selectable instead of fixed?

It used to be a hardcoded 10-PID list in `OBDViewModel`. That broke down once we tested against a real vehicle: no single fixed list fits every car, because vehicles genuinely differ in which PIDs they support — one real-world test connected to a vehicle reporting 51 supported PIDs, only 2 of which overlapped the app's fixed 10, and the rest came back "NO DATA" every cycle. Rather than trying to guess a universally-good fixed list, `PIDPickerView` (Settings → Live Data PIDs) lets the user choose from every mode-1 PID the library exposes as a live sensor reading (`CommandProperties.live == true`, see `Models/PIDSelection.swift`), persisted across launches, applied to the very next poll cycle without a reconnect. The Vehicle card in the dashboard also lists everything the currently connected vehicle reports as supported, so the user has something concrete to pick from rather than guessing blind.

A per-vehicle auto-filtered list (only show/poll PIDs the connected vehicle actually supports) is a natural follow-up, not yet built — the picker currently shows every known PID regardless of connection state, with a star marking ones the connected vehicle has confirmed.

### Why were .fuelLevel and .controlModuleVoltage previously excluded?

Both were bugs in the OBD2 library's mock data manager, present in SwiftOBD2 and inherited by its EVMSwiftOBD2 fork:
- `.fuelLevel`: crashed the process — `String(format: "%02X", someDouble)` was a type mismatch
- `.controlModuleVoltage`: silently returned no data in mock/demo mode

Both are fixed in `AbdulDavids/EVMSwiftOBD2` (the fork DriveOps now depends on — see `/swiftobd2-bug-report.md` and the upstream PR referenced there), so both PIDs are selectable in the picker like any other.

See `/swiftobd2-bug-report.md` for detail and the fix plan.

## Why mirror logs to os.Logger instead of only the in-app Logs tab?

The in-app `logs` array is only visible while the app is running and attached to a view. Once debugging moves to a real adapter on a real device — where you're not always watching the Logs tab, or the app isn't foregrounded — `os.Logger` output in Console.app or Xcode's console is the only way to see what happened. `AppLogger.swift` gives each subsystem area (connection, live data, diagnostics, demo) its own category so the system log can be filtered without wading through everything.

## Connection button UX

Buttons open an info sheet rather than connecting directly. This gives the user context (setup steps, an Open Settings shortcut) before committing to a connection attempt, and avoids a confusing immediate spinner with no explanation.

## Simulator warning

A small warning is shown in the connection card when running in the iOS Simulator, since the OBD2 library hardcodes mock data for Bluetooth and Wi-Fi in that environment. This prevents confusion when BT/Wi-Fi appear to "connect" instantly with mock data instead of asking for a real adapter.

## Why does the AI Mechanic prompt include decoded VIN info?

Both the on-device Apple Intelligence explanation and the external chat provider prompt in `TroubleCodeDetailView` used to describe a trouble code with no vehicle context at all — "Powertrain code P0420" reads the same whether it's on a 2005 economy car or a 2023 hybrid, even though likely causes and fixes genuinely differ by make and age. Since `OBDViewModel.decodedVIN` (from the VIN package, see the "Add VIN decoding" work) already gives us manufacturer/model year/country when the adapter reports a VIN, `OBDViewModel.vehicleContextForPrompt` turns that into a short "a 2019 Honda vehicle (built in Japan)" fragment and both prompt sites prepend/interpolate it.

This is deliberately best-effort: `vehicleContextForPrompt` returns `nil` (not a placeholder like "an unknown vehicle") whenever there's no VIN, the VIN didn't decode, or neither year nor manufacturer came back, so both call sites fall back to exactly the pre-existing generic prompt text with no broken string template. `TroubleCodeDetailView` takes `vm: OBDViewModel?` as an optional (defaulting to `nil`) rather than a required dependency, so it keeps working — vehicle-context-free — for any call site or preview that doesn't have a live view model to pass in.

## Why did the "On-Device AI" toggle become a three-way picker?

Apple's FoundationModels framework ships two distinct language models behind the same `LanguageModelSession` API: `SystemLanguageModel` (fully on-device, always available offline, small context window) and `PrivateCloudComputeLanguageModel` (Apple's server-side model, larger context, but needs network and is subject to a daily per-user quota Apple doesn't publish a fixed number for — see `PrivateCloudComputeLanguageModel.Error` and `.quotaUsage` in the SDK). A boolean "on-device AI enabled" toggle has no way to express "use the bigger cloud one" as a third state, so it became `OnDeviceAIMode` (`.off` / `.systemModel` / `.privateCloudCompute`).

Picking `.privateCloudCompute` doesn't skip the on-device model entirely — `TroubleCodeDetailView.generateExplanation()` tries PCC first (gated behind `@available(iOS 27, *)`, since `PrivateCloudComputeLanguageModel` itself requires it — one OS version ahead of `SystemLanguageModel`'s iOS 26), and falls back to the on-device model on any PCC-specific transport failure (`PrivateCloudComputeLanguageModel.Error` — network failure, quota reached, service unavailable) rather than showing an error. The reasoning: a user who explicitly asked for PCC almost certainly still wants *an* explanation if PCC itself is temporarily down, and the always-available on-device model can usually give them one. A genuine content refusal/guardrail violation from PCC is treated as a real answer, though — that's PCC actually responding, just not with something usable, so it does not fall through to a second attempt on-device.

The old `onDeviceAIEnabled` boolean's `@AppStorage` key isn't reused or deleted outright — `OnDeviceAIMode.loadInitial()` reads it once (if the new `onDeviceAIMode` key has never been set) and migrates `true`/`false` to `.systemModel`/`.off`, so upgrading the app doesn't silently reset anyone's existing preference to a hardcoded default.

### Why is Cloud (Private Cloud Compute) in the enum but not selectable?

Selecting it crashed the app on a real device, every time, with `_assertionFailure` deep inside FoundationModels — not a catchable `LanguageModelSession.GenerationError` or `PrivateCloudComputeLanguageModel.Error`, which is exactly what the `do`/`catch` around `generateWithPrivateCloudCompute()` was written to handle. Apple's own documentation for `PrivateCloudComputeLanguageModel` explains why: "To develop with PCC you must meet certain eligibility requirements... request access to the managed entitlement" (`com.apple.developer.private-cloud-compute`). DriveOps's `DriveOps.entitlements` doesn't have it — the framework apparently doesn't check for the entitlement gracefully before running, it asserts.

Since Apple's approval process for that entitlement isn't something this session can complete, `OnDeviceAIMode.selectableCases` excludes `.privateCloudCompute` from the Settings picker (the enum case itself stays, so the rest of the mode-selection code doesn't need restructuring later), and `loadInitial()` defensively downgrades any already-persisted `.privateCloudCompute` value back to `.systemModel`. `TroubleCodeDetailView.generateExplanation()` keeps its `aiMode == .privateCloudCompute` branch as a second line of defense rather than deleting the PCC code path outright — re-enabling it later (once the entitlement is granted and added to `DriveOps.entitlements`) should just be restoring `.privateCloudCompute` to `selectableCases`.
