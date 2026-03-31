# SwiftOBD2 Bug: `String(format: "%02X", Double)` crash in `mockManager.swift`

**Repo:** https://github.com/kkonteh97/SwiftOBD2  
**File:** `Sources/SwiftOBD2/Communication/mockManager.swift`  
**Severity:** High — crashes on every poll cycle when `.fuelLevel` PID is requested in simulator/demo mode

---

## Description

The mock ECU response generator for the `.fuelLevel` PID passes a `Double` to a `%02X` format specifier, which expects an integer type. This causes `String(format:)` to throw on every invocation, printing the following to the console repeatedly:

```
String(format:locale:arguments:): Provided argument types ["Swift.Double"]
(with inferred specifiers ["%lf"]) do not match the format string's specifiers
[Error Domain=NSCocoaErrorDomain Code=2048
"Format '%02X' does not match expected '%lf'"
UserInfo={NSDebugDescription=Format '%02X' does not match expected '%lf'}]
```

Because this happens inside `mockResponse(forCommand:)`, which is called by `requestPIDs` on every poll interval, the error fires continuously and the entire batch response is silently dropped — meaning **no live data is delivered** to the caller.

---

## Location

`Sources/SwiftOBD2/Communication/mockManager.swift`, inside the `OBDCommand.mockResponse(forCommand:)` extension:

```swift
case .fuelLevel:
    let level = Int.random(in: 0...100)
    let hexLevel = String(format: "%02X", Double(level) * 2.55)  // ← BUG
    return "2F" + " " + hexLevel
```

---

## Fix

Cast the result back to `Int` before passing to `%02X`:

```swift
case .fuelLevel:
    let level = Int.random(in: 0...100)
    let hexLevel = String(format: "%02X", Int(Double(level) * 2.55))  // ← fixed
    return "2F" + " " + hexLevel
```

The OBD-II spec for PID `0x2F` (Fuel Tank Level Input) encodes the value as `A / 255 * 100`, so the raw byte should be `Int(percentage * 2.55)`.

---

## Additional Issue: `.controlModuleVoltage` has no mock response

`OBDCommand.Mode1.controlModuleVoltage` falls through to the `default: return nil` branch in `mockResponse(forCommand:)`, causing `sendCommand` to return `["No Data"]` for that PID. This isn't a crash, but it silently drops the PID from every batch response in demo/simulator mode.

**Suggested fix:** Add a mock response for PID `0x42`:

```swift
case .controlModuleVoltage:
    // PID 0x42: Control module voltage, encoded as A*256+B in millivolts / 1000 = volts
    let voltage = Int(Double.random(in: 13.5...14.5) * 1000)
    let A = voltage / 256
    let B = voltage % 256
    return "42" + " " + String(format: "%02X", A) + " " + String(format: "%02X", B)
```

---

## How to reproduce

1. Add `SwiftOBD2` via SPM
2. Create an `OBDService(connectionType: .demo)` (or run on simulator — it also uses `MOCKComm`)
3. Call `requestPIDs([.mode1(.fuelLevel)], unit: .metric)`
4. Observe the `String(format:)` error in the console and an empty result dictionary returned
