# 2026-11-15 WHOOP Ghidra findings — consolidated integration ledger

This index records the independently observed behavior and the status of integration into STRAP. **Research notes are not production fixes.** No proprietary executable or copied decompiled implementation is included.

| Area | Evidence | STRAP status | Remaining verification |
| --- | --- | --- | --- |
| Resting energy | [Calorie/RHR binary notes](whoop-calorie-rhr-ghidra-2026-11-15.md) | `ios/Strap/Analysis/Calories.swift` uses Mifflin–St Jeor basal estimates, not the WHOOP resting implementation | Verify units, ARM64 parameter mapping, and baseline category before altering code |
| Workout energy | [Calorie/RHR binary notes](whoop-calorie-rhr-ghidra-2026-11-15.md) | Keytel-based active energy, HRR gate, cadence fallback; not WHOOP binary equivalent | Confirm time integration, category selection, HR clipping and paired activity values |
| Strain display lookup | [Sleep/recovery resource notes](sleep-recovery-investigation-2026-11-15.md) | Resource extraction identified a 211-entry nonlinear raw-to-displayed 0–21 strain mapping; no verified raw strain accumulation formula or production integration | Verify table provenance, raw-score units and interpolation, endpoint behavior and sample outputs before using it |
| Recovery-based strain guidance | [Sleep/recovery resource notes](sleep-recovery-investigation-2026-11-15.md) | Resource extraction identified a recovery-to-recommended-strain lookup (observed 0% recovery → 5.0 suggested strain); guidance is distinct from measured strain | Verify complete mapping, rounding, interpolation and independence from the recovery calculation |
| RHR baseline | [Calorie/RHR binary notes](whoop-calorie-rhr-ghidra-2026-11-15.md) | Independent local analysis | WHOOP excerpt shows fetch/cache lifecycle only; not baseline computation |
| Sleep candidate threshold | [Auto-detect threshold notes](whoop-sleep-threshold-ghidra-2026-11-15.md) | `SleepDetect.swift` uses physiological candidate gates | WHOOP's config fallback and app-level threshold are not a replacement for sensor evidence |
| Pending sleep synchronization | [Pending sync notes](whoop-pending-sleep-sync-ghidra-2026-11-15.md) | No confirmed WHOOP-equivalent state polling implementation | Verify timer selector, terminal states, cancellation and overlap before adopting |
| Manual bedtime/wake edits, recovery | [Sleep/recovery notes](sleep-recovery-investigation-2026-11-15.md) | `SleepSession.swift` preserves canonical corrections; `SleepReport.swift` uses complete staged sessions | Reproduce end-time drift and test recalculation on real sensor coverage |
| Health monitor availability | [Health monitor notes](health-monitor-response-states-2026-11-15.md) | Local health calculations | Do not substitute absent HRV/RHR/RR/SpO2 values with fabricated data |

## Precise additional Ghidra reference points

- `WHPApp::startSyncPendingSleep:` `0x10004beb0`; main-queue trampoline `FUN_10004bf28`; timer callback `0x10004c020`; background pending-state check `0x10004c104`.
- `loadCachedCycleEntityForCycleDate:` selector confirmed from thunk `FUN_1089eb8c0`.
- `WHPApp::sleepAutoDetectStartedAt` `0x10004e0b4` returns ivar at `self + 0x170`. Metadata references `0x108a56690` and `0x10c311f17` are **DATA** references, not writes or call sites.
- `HomeViewController.validateSleepDetected` `0x1000a8c58` calls `FUN_1000a88ec`; this alone does not establish onset/staging algorithm.
- `WHPApp::isDetectedSleepOverThreshold` `0x10004dbcc`; config getter `0x100998fac`, fallback 1.0 hour; configured runtime value unknown.
- Resting energy helper `0x1002163b4`, workout energy helper `0x100216764`, total-energy path `0x1002161cc`; RHR fetch `0x10029f008`, worker `0x10029fbb8`, callback `0x10029fc68`.

## Safe merge decision

The above observations are consolidated on `main` as reproducible research pointers. **No change to live sleep/calorie/recovery scoring is justified by these excerpts alone.** Next engineering change should be a narrow tested fix with before/after evidence. In particular, preserve edited sleep bounds during BLE archive replay, treat missing data as unknown, and avoid duplicating pending requests.

## Source integrity

Addresses and constants originate from the user's Ghidra excerpts and existing research notes; these are static interpretations and may be affected by decompiler type/signature uncertainty. Do not represent them as a verified WHOOP specification.
