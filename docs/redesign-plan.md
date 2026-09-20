# DriveOps redesign plan

Status: in progress, 20 September 2026. Based on the current app source, pinned OBD dependency, and supplied RPM screenshot.

## Implementation progress

### Completed in the app

- Added a typed `LiveMetric` boundary with a stable command identity, name, category, numeric value, unit, timestamp and quality state.
- Added one `MetricCatalog` for canonical names, protocol bounds and number formatting. The dashboard no longer needs to identify metrics from an upstream display label such as “RPM”.
- Routed both real and demo readings through that boundary while retaining the existing string data temporarily for older views.
- Added a bounded RPM recovery guard for the pinned dependency's known batch-decoding defect. It only activates when the decoded value contains the `0C` RPM PID echo as its top byte; it extracts the two payload bytes and marks the reading as checked.
- Rejected non-finite and protocol-out-of-range readings before they enter normal history.
- Replaced the live-data list with a saved, ordered Dashboard of chosen sensor tiles. Tiles show a formatted value, unit, short trend and explicit waiting/last-reading state.
- Reworked the old PID selector into an **Add sensors** browser. It uses friendly canonical names, preserves the advanced PID identifier as secondary detail, shows vehicle support, and adds/removes a dashboard sensor in one action.
- Added dashboard edit mode for removing and reordering sensor tiles, plus a calmer sensor detail view with readable history and min/average/max.
- Added distinct waiting, checked, invalid and last-reading states so a missing response is not presented as either zero or a current value.
- Added adapter-free SwiftUI previews for the redesigned dashboard and sensor-detail view, populated with typed readings and sample history for visual review in Xcode.
- Added a typed comparison screen that presents up to four independently scaled charts, so different units are never silently normalised into the same visual scale. It also has an Xcode preview.
- Marked a selected sensor as **Last reading** when no reply has arrived for more than two seconds. Its previous value remains available for context but is no longer presented as live.
- Rebuilt the sensor browser as a searchable catalogue with **Available**, **All sensors** and **On dashboard** filters. It groups sensors by plain-language category and distinguishes responding, supported, waiting, unavailable and untested sensors. Its preview works without an adapter.
- Added a persistent sensor-selection count and request-group warning to the catalogue. Selecting more than six sensors is allowed, but the app now makes the slower multi-request refresh cost explicit.

### Still to implement

- Replace the remaining legacy gauge-grid, chart and comparison views with typed metric views. The primary dashboard, picker and detail view now use typed metrics; the legacy views remain as unused migration code.
- Repair the dependency's batch decoder at its source and add raw-frame replay tests. The current app guard keeps the RPM display useful until that source-level fix is available.
- Add freshness, stale-state handling, per-vehicle dashboard layouts and demand-based polling.

## Product direction

Make DriveOps feel like a vehicle instrument panel with an approachable sensor browser. A user should connect, immediately see useful readings, and add a sensor without needing to understand PIDs, polling, pins, or gauge modes.

The redesign has two equally necessary foundations: trustworthy readings and a clear screen hierarchy. Fix decoding before giving incorrect numbers a more convincing presentation.

## Findings from the current implementation

| Finding | Evidence | Consequence |
| --- | --- | --- |
| Real and demo readings use different names | Dependency calls `010C` “RPM”; simulator calls it “Engine RPM” | Metadata and gauge ranges keyed by display names fail on real readings |
| Values lose their structure at the UI boundary | `OBDViewModel.liveData` stores strings; `GaugeGridView` extracts digits from strings | Units, quality and identity cannot reliably travel with a value; failed parsing becomes zero |
| Detail trusts every numeric sample | `MetricSample` has only timestamp/value; polling adds measurements without validation | Invalid readings contaminate charts, averages and ranges |
| Selection has several meanings | `PIDPickerView` selects polling; `LiveDataCardView` pins control comparison and gauge contents | Users must understand several hidden dependencies to build their dashboard |
| Support is only marked with a star | Picker lists every library live PID | Users can easily select sensors that never respond |
| Removing a selection does not remove its old reading | Real polling merges results into existing dictionaries | Deselected or missing sensors can remain visible with old values |
| Demo ignores selected PIDs | Simulated polling publishes all simulator readings | Demo does not exercise the real selection workflow |
| Details are passed history snapshots | Detail and compare sheets receive arrays rather than observing a metric store | Their live update behavior needs explicit redesign and verification |
| Presentation overstates precision | Fixed one/two decimals, enlarged accessory gauges, four narrow statistics columns | Truncated limits, dense numbers and unnecessary statistics dominate the screen |
| Data quality has no visible state | Last successful values survive partial batches; polling exits on error | A stopped stream can look like a current reading |
| Comparison silently rescales every series | Compare uses each series' observed min/max | Tiny and large changes can look equally significant |

The README and architecture notes contain historical dependency details. Implementation planning uses the actual resolved dependency: `AbdulDavids/EVMSwiftOBD2`, revision `e73d56addd234c2766011ed951d89efce0761ba6`.

## RPM: probable decoding defect, independently of layout

At the pinned revision:

1. The RPM command metadata declares three bytes, covering the PID echo plus two payload bytes.
2. `BatchedResponse.extractValue` takes those three bytes and passes them directly to `CommandProperties.decode`.
3. `CommandProperties.decode` no longer strips the PID byte.
4. The RPM UAS decoder converts all supplied bytes to an integer and multiplies by 0.25.

An illustrative response reproduces the screenshot exactly:

```text
Response payload after framing/mode removal: 0C 10 C4
Incorrect calculation: 0x0C10C4 / 4 = 197,681
Payload-only calculation: 0x10C4 / 4 = 1,073 rpm
```

This is strong source-level evidence of a PID-echo decoding defect. The screenshot alone does not prove those were the actual received bytes or identify the installed app revision. Confirm with a captured response and a replay test. Do not subtract 196,608 in the UI or infer a scaling factor from magnitude.

Standard mode-01 RPM uses two data bytes and a scale of 0.25. Reference: [CSS Electronics PID decoding guide](https://www.csselectronics.com/pages/obd2-pid-table-on-board-diagnostics-j1979). The representable maximum calculated from two bytes is 16,383.75 rpm; that is a protocol boundary, not a vehicle's safe operating limit.

The batch path also takes the first parsed message and consumes values in requested-command order without validating each returned PID. The repair must cover missing/reordered replies and multiple ECUs, not just remove the first byte blindly. Audit all scalar decoder widths: RPM is likely not the only affected sensor.

## Navigation and screen responsibilities

Use four destinations: **Dashboard · Sensors · Diagnostics · Settings**. Move raw logs to Settings → Connection details → Logs, with a shortcut from a connection error.

### Dashboard

- Compact vehicle/connection header: vehicle name, Live / Connecting / Disconnected / Demo, and freshness. Tap for connection details, switch adapter or disconnect.
- When disconnected, show a focused Connect action and Try demo. Keep saved dashboard layout available with unavailable values.
- When connected, show an ordered set of sensor tiles. Start with up to four supported, validated essentials, prioritizing engine speed, vehicle speed, coolant and engine load where available. Do not silently substitute unrelated metrics.
- Tile hierarchy: sensor name → large value and unit → short trend → status when needed. Use neutral surfaces, restrained accent color, readable typography and generous spacing.
- One visible **Edit dashboard** action, with **Add sensor**, reorder and remove. Persist ordering per vehicle.
- **Focus view** enlarges the current dashboard's selected instruments. Its contents never depend on temporary comparison selection.
- Use a normal number and sparkline by default. Offer a bar or dial only when the metric has a meaningful, documented scale.
- iPad uses an adaptive grid and a persistent detail pane; iPhone uses a detail destination. Avoid nested sheets for routine exploration.

### Sensors

Replace “PID Selection” with a searchable sensor catalog.

- Default filter: **Available on this vehicle**. Additional filters: All sensors and Added to dashboard.
- Categories: Engine, Temperatures, Air & fuel, Electrical, Emissions. Search matches plain names, aliases and advanced PID identifiers.
- Each row shows name, brief purpose, formatted latest value if fresh, availability, and Add / Added.
- Availability distinguishes **Responding**, **Reported supported**, **Not checked**, **Not responding**, and **Unsupported**. A support bitmap and a successful response are separate evidence.
- Probe unconfirmed sensors on demand with bounded retries. Absence from the support bitmap alone must not permanently exclude a sensor.
- Offer **Essentials**, **Warm-up**, and **Fuel & air** starting layouts. Include only compatible sensors and explain unavailable entries.
- Adding a sensor puts it on the dashboard and schedules its updates. Removing it stops that demand unless an open detail or comparison still needs it.
- Advanced details expose PID, ECU, decoder, expected units and raw response. Technical identifiers are secondary to the normal workflow.
- Offline users can edit a saved layout; availability remains Unknown until connected. A deliberately empty dashboard stays empty after relaunch.

### Sensor detail

Replace the screenshot's oversized gauge and eight statistics with this hierarchy:

1. Plain sensor name and live status.
2. Large, correctly formatted current value with unit, for example **1,073 rpm**. This is an illustrative corrected value, not a verified vehicle reading.
3. Readable timeline with time and unit labels, selectable 30-second / 2-minute / 5-minute windows, and inspection of individual samples.
4. Min / Average / Max for the selected window, in adaptive columns. Collapse to rows at large text sizes.
5. A short “What this measures” explanation.
6. **Add to dashboard** and **Compare** actions.
7. Expandable “More details” for sample count, variability, source and decoding diagnostics.

Use linear chart interpolation initially, so rendering does not introduce smooth overshoot between samples. Leave gaps for missing/invalid data. Separate a gauge's instrument scale from a chart's visible range. Offer Full scale / Fit data where useful, keeping the active scale clear and stable while inspecting.

Do not label generic hardcoded bands “Normal” for every vehicle. Engine type, warm-up state and operating conditions matter. Health bands require documented vehicle/context rules; otherwise provide explanation without a green health judgment. A rising reading is not inherently good.

### Compare

- Explicit **Compare** action opens a dedicated selection state. Start with two metrics; support up to four using stacked charts.
- Default to aligned timelines with each metric's own units and axis. Inspection shows values at the shared time and their actual sample timestamps; do not invent simultaneous samples.
- An optional **Relative change** overlay may rescale series, but label the transformation and keep actual values accessible. It is a visualization transform, never stored measurement data.
- Dashboard membership and comparison membership remain independent.

### Diagnostics and Settings

- Diagnostics shows the latest scan time, vehicle and ECU context, scan progress and errors, then trouble codes with explanations. Keep code clearing a deliberate, separate action with its consequence explained.
- Preserve existing AI explanation options and vehicle context; separate generated explanations from measured evidence. No AI model participates in decoding or correcting readings.
- Settings contains units, saved vehicle layouts, adapter preferences, existing AI preferences, appearance/accessibility options where needed, and troubleshooting logs.
- Connection setup is one guided flow: choose transport/adapter → connect → discover sensors → show dashboard. Retain platform-specific Bluetooth/Wi-Fi help when relevant.

## Data interpretation and normalization

Use a deterministic pipeline:

```text
Raw adapter response + ECU + receipt time
  → validate framing and response service
  → identify PID and extract its exact payload
  → decode using the registered sensor definition
  → validate type, unit, finite value and protocol bounds
  → store typed reading and quality state in canonical units
  → convert units for user preference
  → format once for all screens
```

Known PIDs tell us the format, signedness, byte order, scale, offset and unit. Manufacturer-specific data requires an explicit definition for the correct vehicle/protocol. Unknown data stays unsupported/raw; neither heuristics nor an LLM should guess a displayable measurement.

### Proposed responsibilities

| Component | Responsibility |
| --- | --- |
| `MetricID` | Service + PID + optional subfield; source ECU retained separately so different ECUs cannot silently overwrite each other |
| `MetricDefinition` | Name, aliases, category, scalar/enum/flags/composite type, canonical unit, precision, protocol bounds and optional display scale |
| `MetricReading` | Definition ID, source ECU/session, typed value, timestamp, quality and optional raw-response reference |
| `MetricStore` | Current state and time-based history; only validated samples feed normal statistics |
| `MetricFormatter` | Locale-aware numbers, unit conversion, precision and missing-state labels for every view |
| `VehicleProfile` | Stable local vehicle identity, optional VIN association, observed support and saved ordered dashboard |
| `PollingCoordinator` | Union of active dashboard/detail/compare demands, priorities, measured cadence, retries and backoff |

Keep connection orchestration in `OBDViewModel` during migration; extract the reading pipeline without requiring a whole-app rewrite. The third-party adapter boundary should preserve raw response and source metadata; this likely requires extending the fork's current measurement-only API.

### Formatting policy

| Metric | Default display | Stored value |
| --- | --- | --- |
| Engine speed | `1,073 rpm` | Full decoded precision |
| Speed | `87 km/h` or converted `54 mph` | Canonical speed |
| Temperature | `91 °C` or converted `196 °F` | Canonical temperature |
| Throttle/load | `24%` | Full decoded percentage |
| Module voltage | `14.2 V` | Full decoded voltage |
| Air flow | `12.4 g/s` | Full decoded mass flow |
| Enumerated state | Named state | Typed enum, not a gauge |
| Flags/composite response | Named statuses/subreadings | Structured fields, not a concatenated number |

Examples use English formatting; apply the user's locale for grouping and decimal separators. Round only at presentation, with metric-specific precision. Never parse a rendered string back into measurement data.

### Quality and freshness

- Model Valid, Waiting, Stale, Invalid, No response, Unsupported and Disconnected explicitly.
- Invalid RPM shows **— rpm · Invalid reading**, with explanation and raw diagnostics. Do not show zero, clamp it to a plausible value, or include it in averages.
- A last valid value may remain visible only with an explicit stale/last-updated label; never present it as current after an invalid response or disconnect.
- Protocol-invalid readings are rejected. Unusual but protocol-valid readings remain visible with context; a presumed normal operating range is not grounds for deletion.
- Start freshness policy at `max(3 × expected metric interval, 2 seconds)`, then tune against real adapters. Track freshness per metric rather than per batch.
- Retain a bounded five-minute history with timestamps and a hard memory cap; downsample for drawing without smoothing stored evidence. If available history is shorter, show its actual duration.
- Partial responses must age missing metrics, not refresh their timestamps. Repeated failures trigger bounded backoff and visible degraded status; cancellation/disconnect stops polling cleanly.
- Prioritize visible fast-changing instruments; poll slower-changing metrics less often. Determine batching from adapter/protocol behavior and fall back to individual requests when needed. Show measured update rate in connection details.
- Use the same definitions and store for demo and real data. Add recorded-frame replay fixtures because a numeric simulator alone cannot test transport decoding.

## Delivery sequence and acceptance gates

### 1. Establish trustworthy decoding

Capture one real RPM exchange with adapter protocol, ECU, request, raw reply and decoded result. Create a replay regression for the suspected PID echo. Repair extraction in the dependency fork and audit affected decoders; update the app's pinned revision only after tests pass.

Acceptance: `41 0C 10 C4` produces 1,073 rpm after transport framing is handled; PID bytes, padding, missing/reordered replies and responses from multiple ECUs cannot become sensor values. Add zero/max, truncated, malformed, negative-response and non-CAN fixtures for supported transports. Confirm the fix on a real adapter; demo success is insufficient.

### 2. Introduce the typed metric layer

Add definitions, source-aware readings, quality states, one formatter and time-based history. Route both real and demo data through it. Remove number extraction from strings and name-based metadata lookups as consumers migrate.

Acceptance: RPM/Engine RPM aliases identify the same definition; unit conversion and locale formatting agree across tiles/details/comparison; NaN/infinity/invalid samples never enter normal chart statistics; stale values cannot look live.

### 3. Build selection and dashboard together

Implement vehicle profiles, sensor browser, supported-first defaults, Add/Edit/reorder and demand-based polling. Migrate existing saved hex PID selections into an ordered layout using a stable catalog order; preserve unavailable choices with status. Current temporary pins have no durable state to migrate.

Acceptance: add a known sensor in at most three taps from Dashboard, without visiting Settings; removing it removes its tile immediately; empty and customized layouts survive relaunch; vehicle switching cannot blend readings or support lists; demo respects selection.

### 4. Replace detail, comparison and focus displays

Build shared metric tiles, formatting and chart styles. Remove enlarged accessory gauge labels and crowded statistics. Subscribe detail/compare to the live store by ID. Move logs and connection information into the new hierarchy.

Acceptance: values continue updating while details are open; no clipped units/numbers on the smallest supported phone or at accessibility text sizes; charts show invalid gaps and real time coverage; comparison is understandable without knowing normalization mathematics. Verify light/dark, landscape, iPad and VoiceOver, without announcing every live sample.

### 5. Validate the whole experience

Run fixture tests and UI workflows for first connection, no supported sensors, failed discovery, unsupported selection, partial data, disconnect/reconnect, app background/foreground, vehicle switching and unit changes. Check polling cancellation, duplicate tasks, chart memory and update cadence during a sustained real session.

Release gate: real-adapter RPM agrees with an independent reading at idle and changing engine speed; expected sampling latency is documented; decoder replay tests pass; screenshots of all major states have been visually reviewed. Start with a small trusted metric set and expand catalog coverage only as definitions are validated.

## Scope and remaining decisions

The first release includes current live metrics, current-session history, sensor customization, diagnostics and existing AI explanations. Persistent trip recording, exports, custom manufacturer-PID authoring and automatic vehicle health scoring are later projects, not prerequisites for simplifying the app.

Proceed with native iOS styling, metric units by default with user overrides, and a local vehicle profile when VIN is unavailable. The key remaining evidence requirement is an actual adapter response from the screenshot's setup. It blocks confirming that incident's exact cause, but does not block designing the new UI or fixing the demonstrated batch-decoding contract.
