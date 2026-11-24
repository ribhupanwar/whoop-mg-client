# STRAP Remaining Gaps, Priorities & Hardware Verification Ledger

**Document ID:** `docs/research/STRAP_REMAINING_GAPS_AND_PRIORITIES.md`  
**Repository:** `ribhupanwar/whoop-mg-client`  
**Target Hardware:** WHOOP 5.0 (Maverick) & WHOOP MG (Goose)  
**Binary Reference:** Official iOS WHOOP 5.80.2 ARM64 (Ghidra 12.2)  
**Date:** November 24, 2026  
**Status:** COMPLETE & PRIORITIZED  

---

## 1. Executive Summary

This document serves as the master engineering ledger prioritizing all resolved, active, and deferred gaps across STRAP's protocol, biometric, UI, and hardware integration pipelines.

Findings are categorized strictly by severity:
- **P0:** Data corruption, unsafe hardware behavior, severe biometric defects, or crash hazards.
- **P1:** Significant functional bugs, logic errors, or calculation discrepancies.
- **P2:** UI, performance, diagnostics, and reliability enhancements.
- **P3:** Experimental features, longitudinal research candidates, or platform extensions.

Every item is accompanied by exact file paths, line references, external repository citations, root cause analyses, regression tests, and pull request links.

---

## 2. Categorized Findings & Prioritized Gap Ledger

| Finding | Severity | STRAP Path | External Reference | Evidence | Root Cause | Proposed Fix | Regression Test | Status | PR | CI Run |
|:---|:---:|:---|:---|:---|:---|:---|:---|:---:|:---:|:---:|
| **Premature Flash ACK Buffer Trim** | **P0** | `ios/Strap/Band/BandLink.swift:2245` | `ryanbr/noop`<br>`PROTOCOL_TRANSPORT.md:221` | Band trims flash sectors upon receiving `0x17` token. | If app sends ACK before local disk write completes, interrupted offload destroys uncommitted sensor data. | Commit chunk to SQLite WAL database *before* sending ACK token `0x17`. | `BandConnectionStateMachineTests:testCommitBeforeAckSafety` | **FIXED** | PR #172 | [Run 45347367363](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367363) |
| **Gen4 SET_CLOCK Command Contamination** | **P0** | `ios/Strap/Band/BandLink.swift:1840` | `andyguzmaneth__whoop4-ble`<br>`PROTOCOL.md:39` | Gen4 5-byte `SET_CLOCK` (`0x0A`) sent to Gen5 hangs BLE state machine. | Offsets and command bytes differ between WHOOP 4.0 and Gen5 (`0xFD4B`). | Enforce strict isolation; never emit Gen4 clock commands on Gen5 connections. | `ProtocolTests:testGen5CommandIsolation` | **FIXED** | PR #172 | [Run 45347367363](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367363) |
| **Active ECG Command Generation Freeze** | **P0** | `ios/Strap/Protocol/MGEcgPacket.swift:5` | `ryanbr/noop`<br>`PROTOCOL_ECG.md:32` | NOOP Issue #891: active ECG commands (`0x7B`–`0x7F`) cause hardware lockup without data. | MG firmware requires unverified internal lead calibration state. | Restrict ECG to passive waveform reception; quarantine active commands. | `MGEcgPacketTests:testPassiveEcgBounds` | **FIXED** | PR #172 | [Run 45347367363](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367363) |
| **V18 Unused Slot Dirty Padding Discard** | **P1** | `ios/Strap/Protocol/V18Record.swift:55`<br>`whoop/records.py:decode_v18` | `ribhupanwar/dsta`<br>`PulseForge/Whoop5RRDecoder.swift` | Issue #171: V18 records with $count < 4$ and dirty padding bytes discarded declared beats. | Parser treated trailing non-zero bytes as record corruption. | Extract declared beats ($count \le 4$); flag `rrPaddingValid = false` for telemetry diagnosis. | `test_v18_rr_padding_171.py`<br>`SensorTruthTests:14` | **FIXED** | PR #173<br>PR #203 | [Run 45347367533](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367533) |
| **Python vs Swift RHR Calculation Drift** | **P1** | `whoop/metrics.py:resting_heart_rate`<br>`ios/Strap/Analysis/Hrv.swift:45` | `whoop-5802-algorithm-parity` | Python produced mean of rolling means ($80.2\text{ BPM}$); Swift produced median ($78.6\text{ BPM}$). | Python implementation diverged from production Swift median algorithm. | Aligned Python `resting_heart_rate` to median of 300s rolling means. | `tests/rhr_algorithm_comparison.py` | **FIXED** | PR #174 | [Run 45347367533](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367533) |
| **Sparse Sensor Gap Movement Spurious Accumulation** | **P1** | `ios/Strap/Analysis/SleepDetect.swift:85` | Research Capture `sleep-1795375775...csv` | Disconnected motion ticks separated by minutes accumulated into 15s wake bouts. | Counter lacked contiguous timestamp gap reset condition. | Reset `movingSeconds = 1` whenever $u > \text{last} + 1$. | `SensorTruthTests:15` | **FIXED** | PR #203 | [Run 45347367363](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367363) |
| **Bathroom Interruption Sleep Truncation** | **P1** | `ios/Strap/Analysis/SleepDetect.swift:142` | Issue #126 Forensic Audit | Brief nocturnal awakenings (< 5 min) prematurely split sleep into multiple sessions. | Lack of grace window and rustle backtracking. | Implemented 5-minute awakening merge window and position rustle recovery. | `SleepBathroomBreakMergingTests` | **FIXED** | PR #136 | [Run 45008007991](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45008007991) |
| **Activity Asset Collision on Water Polo** | **P2** | `ios/Strap/Views/Components/ActivityIcons.swift` | Issue #164 Asset Audit | Duplicate asset declaration for Water Polo icon caused compiler warnings. | Clashing icon names in asset registry dictionary. | Renamed asset to `water_polo_icon` with SF Symbol fallback. | `ActivityIconRegistryTests` | **FIXED** | PR #175 | [Run 45008007991](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45008007991) |
| **Detailed HRV Diagnostics Export** | **P2** | `ios/Strap/Analysis/AnalysisTypes.swift:35`<br>`whoop/metrics.py:hrv_detailed_diagnostics` | WHOOP 5.80.2 Forensics Matrix | Lacked visibility into NN beat rejection reasons during live streaming. | Diagnostics struct omitted rejected beat categorization. | Added `HrvDetailedDiagnostics` with accepted NN, out-of-range, and ectopic breakdown. | `SensorTruthTests:16` | **FIXED** | PR #203 | [Run 45347367363](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367363) |
| **Automatic Rolling Daily Database Backup** | **P2** | `ios/Strap/Analysis/StrapBackup.swift:202` | `OpenStrap/edge`<br>`lib/data/auto_backup.dart` | Users must manually trigger database export from settings pane. | STRAP has atomic backup engine but lacks automatic launch trigger. | Wire existing `StrapBackup` to execute automated rolling 7-day snapshot on app launch. | `StrapBackupTests:testRollingDailySnapshot` | **CANDIDATE** | Next PR | Pending |
| **SpO₂ Absolute Clinical Calibration** | **P3** | `whoop/records.py:decode_spo2_candidate`<br>`ios/Strap/Protocol/V18Record.swift:105` | `SPO2_OPENWHOOP_GAP_AUDIT.md` | SpO₂ displayed as uncalibrated percentage without medical device clearance. | Sensor optical variations require factory calibration lookup tables. | Retain candidate display with explicit non-clinical disclosure. | `CaptureCompatibilityTests` | **ACTIVE CANDIDATE** | N/A (By Design) | [Run 45347367533](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/45347367533) |
| **Siri Shortcuts & Home Screen Widgets** | **P3** | `ios/Strap/` (App Target) | `OpenStrap/edge`<br>`lib/widget/widget_service.dart` | Users cannot view daily strain/recovery rings on iOS lock screen. | Requires separate WidgetExtension and AppIntents framework targets. | Defer to dedicated UI platform release to avoid bloating core client. | N/A | **DEFERRED** | Future Release | N/A |

---

## 3. Physical-Band Hardware Verification Gates

While all 406 Python tests and 790+ iOS unit tests pass in automated simulation, the following four physical-band verification gates require hardware testing on genuine WHOOP 5.0 and WHOOP MG bands:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   PHYSICAL HARDWARE VALIDATION GATES                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. GATT Subscription Race Condition Gate:                                   │
│    Verify on real Nordic nRF5340 that Command Read, Data Read, and          │
│    Event Read subscriptions complete before CLIENT_HELLO is transmitted.    │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. Multi-Day Flash Wrap & Chunk Acknowledgment Gate:                         │
│    Verify that offloading >86,400 records (>24 hours offline) safely wraps   │
│    internal flash ring buffers and reclaims memory only after 0x17 ACK.     │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. WHOOP MG Hardware Passive ECG Streaming Gate:                            │
│    Verify whether physical MG hardware emits R17 packets upon thumb-to-bezel│
│    contact without requiring active 0x7B generation commands.               │
├─────────────────────────────────────────────────────────────────────────────┤
│ 4. SideStore IPA In-Place Upgrade Gate:                                     │
│    Verify that installing the newly packaged unsigned IPA via SideStore     │
│    preserves existing CoreData/SQLite records, paired strap UUID, and keys. │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Prioritized Next Action Plan

1. **Immediate (PR #203 Merged):** Complete integration of PR #203 containing master sensor matrix, detailed HRV diagnostics, `rrPaddingValid` diagnostics, and sparse timestamp disturbance fixes.
2. **Next Minor PR (P2):** Automate `StrapBackup.swift` rolling daily snapshots on app foregrounding (inspired by OpenStrap Edge `auto_backup.dart`).
3. **Hardware Lab Session:** Execute the four physical-band verification gates on physical WHOOP 5.0 / MG hardware.
