# STRAP Cross-Repository Integration Audit

**Phase:** 12 — Worldwide Open-Source Research & Safe Integration
**Date:** 2026-11-24
**Target Repository:** `https://github.com/ribhupanwar/whoop-mg-client`
**Base Branch:** `kilo/windy-canyon-wxm`
**Base Commit SHA:** `a784320d47f66f6f448119e9db6d22dfc2db746f`
**Target Deliverable:** `docs/research/STRAP_CROSS_REPOSITORY_INTEGRATION_AUDIT.md`

---

## 1. Scope and Method

This audit surveys public WHOOP reverse-engineering and wearable-health repositories, compares their documented behavior against STRAP's production Python reference and iOS implementation, and records candidate integrations. No third-party source code was copied; all findings are clean-room protocol facts. Experimental algorithms remain separated from production.

Reference repositories investigated (URLs verified against prior audits in `docs/research/`):

| # | Repository | Role |
|---|-----------|------|
| 1 | `OpenStrap/edge` | Firmware-aware BLE decoding, sensor packets, RR handling, IMU, sync |
| 2 | `OpenStrap/protocol` | Packet structures, command handling, firmware differences, protocol tests |
| 3 | `OpenStrap/analytics` | HRV, RHR, sleep, activity detection, signal quality, confidence |
| 4 | `ryanbr/noop` | WHOOP sensor processing and analytics |
| 5 | `gdorgian/aura` | Wearable health analytics and UI concepts |
| 6 | Other maintained WHOOP reverse-engineering repos (johnmiddleton12/wearable, jaredwerba/andyguzmaneth__whoop4-ble, etc.) | Gen4/Gen5 contrast |

License posture: OpenStrap projects are AGPL-3.0; NOOP is PolyForm Noncommercial 1.0.0; wearable has no license. STRAP performs clean-room reimplementation from documented wire protocol facts only and imports no external source.

---

## 2. STRAP Production Baseline

STRAP's production implementations under audit:

- BLE framing/decoding: `ios/Strap/Protocol/V18Record.swift`, `MGEcgPacket.swift`, `BandLink.swift`
- Historical transfer: `BandLink.swift:2245` (commit-before-ACK), archive persistence before `0x17` ACK token
- Metrics: `whoop/` Python reference + `ios/Strap/Analysis/` (HRV, RHR, strain, recovery, sleep staging, respiration, steps, VO2max, calories)
- Backup: `ios/Strap/Analysis/StrapBackup.swift:202`
- Alarms: `ios/Strap/WakeAlarm.swift:140`
- History coverage: `HistoryCoverage.swift`, `HistoryCoverageBatchRegressionTests.swift`

Test baseline: Python cross-platform matrix 373/373 tests (per prior audit). iOS simulator build green.

---

## 3. Comparison Matrix

### 3.1 BLE Packet Decoding and Firmware Compatibility
- **Source:** OpenStrap/protocol (packet structures, firmware differences, protocol tests); NOOP `PROTOCOL_SENSORS.md` (R18 124-byte summary, HR byte 22, RR count byte 23, RR words bytes 24+2i, accel byte 41, activity class byte 63).
- **STRAP:** `V18Record.swift:24` decodes 124-byte R18, parses 1/1024s RR ticks, extracts dynamic acceleration. Gen5/MG framing isolated from Gen4 (verified in prior audit).
- **Gap:** None confirmed beyond documented Gen4 isolation. No action.

### 3.2 RR Interval Extraction and Artifact Filtering
- **Source:** NOOP RR handling docs; OpenStrap/analytics signal quality.
- **STRAP:** RR padding handling covered by `tests/test_v18_rr_padding_171.py`.
- **Gap:** None newly confirmed. Keep regression fixture.

### 3.3 HRV/RHR Accuracy and Confidence
- **Source:** OpenStrap/analytics (HRV, RHR, confidence).
- **STRAP:** `tests/test_metrics.py`, `test_algorithm_parity_5802.py`; HRV/RHR epoch diagnostics in `tests/hrv_rhr_epoch_diagnostics.py`.
- **Gap:** None confirmed beyond existing validated metrics. No regression allowed.

### 3.4 Sleep Onset, Staging, Awakenings, Final Wake
- **Source:** OpenStrap/analytics sleep; NOOP.
- **STRAP:** `tests/test_sleep_analysis.py`, `test_sleep_stage.py`, `test_sleep_export_audit.py`.
- **Gap:** None newly confirmed.

### 3.5 Accelerometer Cadence and Automatic Activity Recognition
- **Source:** OpenStrap/edge; NOOP.
- **STRAP:** `tests/test_activity.py`, `test_steps.py`; run/walk/workout detection per README.
- **Gap:** None newly confirmed.

### 3.6 GPS and Live Workout Recording
- **Source:** OpenStrap/edge.
- **STRAP:** Live workout sessions with zone-time allocation (README).
- **Gap:** GPS integration not present; deferred (no hardware validation).

### 3.7 SpO2 Validity and Calibration Safety
- **Source:** NOOP; prior `SPO2_OPENWHOOP_GAP_AUDIT.md`.
- **STRAP:** SpO2 treated as unvalidated candidate (README honest gaps).
- **Gap:** No validated SpO2; deliberate absence preserved. No change.

### 3.8 VO2 Max Estimation Provenance
- **Source:** OpenStrap/analytics; Uth 2004.
- **STRAP:** `15.3 × HRmax / HRrest`, labels age-predicted fallback.
- **Gap:** None. Provenance documented.

### 3.9 Healthspan Input Completeness
- **Source:** gdorgian/aura.
- **STRAP:** Healthspan metric charts and prior-value markers (PR #216).
- **Gap:** None newly confirmed.

### 3.10 Data Synchronization and Reconnection
- **Source:** NOOP commit-before-ACK contract.
- **STRAP:** Implemented per prior audit.
- **Gap:** None.

### 3.11 Battery Efficiency and Background Execution
- **Source:** OpenStrap/edge.
- **STRAP:** No scheduled rolling backups (identified candidate in prior audit).
- **Gap:** Candidate: automate existing backup on app launch with rolling 7-day snapshots. Experimental/deferred; not P0.

### 3.12 Crash Prevention and Performance
- **Source:** All.
- **STRAP:** `tests/test_production_stability_hardening.py`, `test_stuck_detector.py`.
- **Gap:** None newly confirmed.

### 3.13 WHOOP-Inspired UI and Chart Interactions
- **Source:** gdorgian/aura.
- **STRAP:** UI parity tests `test_whoop_ui_parity.py`, `test_visual_regression.py`.
- **Gap:** None newly confirmed.

---

## 4. Independently Verified Improvements (P0/P1)

None newly verified beyond already-implemented items. All candidate integrations either already present or require hardware validation / separate extension targets. No code changes made in this phase beyond this audit document.

---

## 5. License Considerations

- No external source code imported.
- Clean-room reimplementation from documented protocol facts.
- AGPL-3.0 and PolyForm boundaries respected (no copying).

---

## 6. Remaining Hardware Validation

- GPS/live workout recording on device.
- Scheduled backup behavior on app launch.
- ECG passive capture validation (commands quarantined per NOOP issue #891).

---

## 7. Integration Status Summary

| Candidate | Status |
|-----------|--------|
| Gen5/MG framing isolation | Implemented & validated |
| Commit-before-ACK historical transfer | Implemented & validated |
| RR padding handling | Implemented & tested |
| HRV/RHR metrics | Implemented & validated |
| Sleep staging | Implemented & tested |
| Activity detection | Implemented & tested |
| SpO2 (unvalidated candidate) | Deliberately absent |
| VO2 max provenance | Implemented & documented |
| Scheduled backups | Deferred (candidate) |
| GPS workout recording | Deferred (hardware) |

---

## 8. Conclusion

STRAP's production implementations already cover the independently verified, safely testable improvements identified across the surveyed repositories. No P0/P1 code change is warranted in this phase without hardware validation. This audit is the deliverable for Phase 12.
