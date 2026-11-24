# STRAP Master Accuracy, Performance & WHOOP Parity Audit

**Date:** 2026-11-24
**Branch audited:** `research/sleep-forensics-validation` (uncommitted changes present)
**Last main commit reviewed:** `fb69738 merge: reconcile with main (PRs #172-176)`

## 1. Already implemented and verified

- Python test suite: **412 passed, 1 skipped, 553 subtests passed** (23.87s) on current working tree.
- In-progress sleep/health work adds `merge_nocturnal_periods` (whoop/health.py:968) with 120 lines of new regression tests in tests/test_health.py (NOOP parity: awake-in-bed onset, bathroom-break merging, HR-drop gating).
- SleepDetect.swift modified (+142 lines) on the same branch.
- Recent main merges #172–#176 include V18 RR padding fix, autonomic onset gate, max sleep window, disturbance harmonization, RHR median alignment, sensor-truth RR padding test alignment.

## 2. Existing work requiring validation

- Swift/iOS production path cannot be built in this environment (no Xcode). Python-green ≠ iOS-green; WorkoutRecorder test failures (historical iOS run 45363641352) remain unverified here.
- Uncommitted changes on `research/sleep-forensics-validation` must be reviewed for data-safety and manual-edit recalculation before merge.

## 3. Genuine missing features / open gaps

- Physical-band validation of V21/RawDataRev21 7-RR-slot decoding, live Type-40 vs historical Type-47/52 consistency, RTC drift handling.
- WorkoutRecorder iOS assertions (PRs #206–#208) need re-verification against latest main CI.
- SpO2 candidate-vs-calibrated provenance, VO2 max personalized inputs, healthspan orb animation profiling.

## 4. Cross-repository improvements worth adopting

- NOOP/OpenStrap sleep onset + bathroom-merge logic (already partially adopted via merge_nocturnal_periods).
- Independently reimplement, do not copy AGPL code; verify licensing per improvement.

## 5. New Ghidra findings

- None new this pass. Historical findings index (docs/research/ghidra-findings-index-2026-11-15.md) must be reconciled before any new analysis.

## 6. Confirmed bugs

- None newly confirmed beyond in-progress branch scope; all current tests green.

## 7. Implemented fixes this pass

- Verified existing in-progress changes compile/test (Python). No new code changes made this pass to avoid duplicating ongoing work.

## 8. Test results

- Command: `python -m pytest -q`
- Result: 412 passed, 1 skipped, 553 subtests passed, 23.87s.
- iOS/Swift tests: not runnable in this environment.

## 9. Performance benchmarks

- Not measured this pass (no profiling tooling available in sandbox).

## 10. PRs / merges / CI

- See git log on main: PRs #172–#176 merged. Branch `research/sleep-forensics-validation` unmerged with uncommitted changes.

## 11. Physical-band validation still needed

- Multi-night sleep captures, wrist-off intervals, duplicate history sync, RTC corruption, night workouts, manual sleep edits.

## 12. Remaining P0/P1/P2 work

- P0: Verify iOS WorkoutRecorder assertions; BLE persist-before-ACK / cursor advancement fault injection; HRV RR source selection across retransmissions.
- P1: SpO2/VO2/temperature/respiratory-rate provenance and baselines; UI performance profiling.
- P2: Healthspan orb animation CPU/GPU; chart rendering on large datasets.

## Reconciliation of contradictory parity claims

- Python test green status does not imply iOS production parity. All parity claims require dual-path (Python + Swift) verification plus physical-device evidence.
- Uncommitted in-progress work is substantial and tested in Python only; Swift side unverified.
