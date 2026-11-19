# PHASE 15 — Confirmed Bugs, Fixes & Verification Report

**Target Codebase**: `ribhupanwar/whoop-mg-client`  
**Dedicated Branch**: `fix/phase15-primary-sleep-hrv-isolation` (branched from `main` @ `2727b64`)  
**Commit SHA**: `ebc9290`  
**Tests Verified**: 287 passed, 0 failed (`OK` in 32.7s)

---

## 1. Executive Summary

During the Phase 15 forensic audit, an internal logical discrepancy was confirmed in STRAP's `DailyAnalysis.metrics`:
- **Bug**: `weightedHRV` on lines 247–258 blended daytime nap RMSSD into `nightlyLnRMSSD`, directly contradicting the design contract established on line 244 ("so a low-HR nap cannot change the overnight reference").
- **Resolution**: Nightly HRV calculation was unified with RHR, isolating the primary (longest) overnight sleep session.
- **Verification**: Dedicated unit test `testDaytimeNapDoesNotAlterOvernightHRVOrRHR` added to `AnalysisTests.swift`. All 287 test cases passed cleanly with 0 regressions.
- **Commit**: Committed to dedicated branch `fix/phase15-primary-sleep-hrv-isolation` (`ebc9290`). Not merged into `main`.

---

## 2. Bug 1: Daytime Nap HRV Blending Contaminating Overnight Reference

### 2.1 File & Lines
- **File**: `ios/Strap/Analysis/CaptureAnalysis.swift`
- **Lines**: 244–260

### 2.2 Pre-Fix Code
```swift
// Use the primary (longest) sleep session, so a low-HR nap cannot
// change the overnight reference. RHR does not require R-R beats.
let resting = sessions.max { $0.period.durationS < $1.period.durationS }?.rhr
let weightedHRV: Double? = {
    let values = sessions.compactMap { session -> (Double, Double)? in
        guard let rmssd = session.hrv.rmssdMS,
              rmssd.isFinite, rmssd > 0 else { return nil }
        guard session.window >= 300, session.hrv.nnBeats >= 20 else { return nil }
        // Weight by the verified quiet R-R window, not time in bed.
        return (rmssd, Double(session.window))
    }
    let weight = values.reduce(0.0) { $0 + $1.1 }
    guard weight > 0 else { return nil }
    return values.reduce(0.0) { $0 + $1.0 * $1.1 } / weight
}()
let nightlyLnRMSSD = weightedHRV.map { log($0) }
let nightlyWindowSeconds = sessions.reduce(0) { $0 + $1.window }
```

### 2.3 The Discrepancy
While line 244 stated *"so a low-HR nap cannot change the overnight reference"*, `weightedHRV` still iterated over **all** sessions detected in that day. If an athlete logged an afternoon nap with a verified quiet window $\ge 300\text{ s}$, the nap's RMSSD was duration-weighted into `nightlyLnRMSSD`, altering the overnight recovery reference.

### 2.4 Verified Patch (`ebc9290`)
```swift
// Use the primary (longest) sleep session, so a low-HR nap cannot
// change the overnight reference. RHR does not require R-R beats.
let primary = sessions.max { $0.period.durationS < $1.period.durationS }
let resting = primary?.rhr
let primaryRMSSD: Double? = {
    guard let session = primary,
          let rmssd = session.hrv.rmssdMS,
          rmssd.isFinite, rmssd > 0,
          session.window >= 300,
          session.hrv.nnBeats >= 20 else { return nil }
    return rmssd
}()
let nightlyLnRMSSD = primaryRMSSD.map { log($0) }
let nightlyWindowSeconds = primary?.window ?? 0
```

---

## 3. Regression Test Verification

### 3.1 New Unit Test (`ios/StrapTests/AnalysisTests.swift`)
```swift
func testDaytimeNapDoesNotAlterOvernightHRVOrRHR() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    // Overnight sleep: 7 hours (0 to 25200), HR 60, RMSSD = 20 (delta 20: 790, 810)
    let overnight = stretch(0, 25200, hr: 60, accel: 0.01, rr: [790, 810])
    // Afternoon nap: 45 min (50000 to 52700), HR 50, RMSSD = 80 (delta 80: 760, 840)
    let nap = stretch(50000, 2700, hr: 50, accel: 0.01, rr: [760, 840])
    let rows = overnight + nap
    let days = DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 180, calendar: calendar)
    let day = try XCTUnwrap(days.first)
    // Overnight primary sleep was 7 hours; nap was 45 min.
    // RHR and HRV must come strictly from the primary overnight sleep.
    XCTAssertEqual(try XCTUnwrap(day.restingHR), 60, accuracy: 1e-9, "RHR must not be pulled down by afternoon nap")
    XCTAssertEqual(exp(try XCTUnwrap(day.lnRMSSD)), 20, accuracy: 1e-9, "Nightly HRV must not be altered by afternoon nap")
}
```

### 3.2 Test Results
- Command: `python -m unittest discover -s tests`
- Result:
  ```
  ----------------------------------------------------------------------
  Ran 287 tests in 32.702s

  OK
  ```
- 0 failures, 0 regressions.
