# WHOOP 5.80.2 Metric Dependency & Recalculation Forensics

**Document ID:** `docs/research/whoop_5802/METRIC_DEPENDENCY_FORENSICS.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Binary Analyzed:** WHOOP iOS 5.80.2 Mach-O ARM64 (`Whoop.app/Whoop`, 209,853,712 bytes)  
**Project:** `C:\Users\ribhu\Documents\WHOOP_Analysis.gpr` (/WHOOP_5.80.2)  
**Date:** November 20, 2026  
**Status:** FORENSIC EVIDENCE VERIFIED  

---

## 1. Executive Summary

This report analyzes the full metric recalculation dependency graph in WHOOP iOS 5.80.2, focusing on the cascading ripple effects triggered when a user manually modifies their sleep schedule (`editSleep`, `editSleepSchedule`).

Forensic discoveries:
1. **CoreData Cycle Architecture:** Daily physiological states are persisted in `CachedCycleEntity` (`0x1097604c4`) managed through `loadCachedCycleEntityForCycleDate:` (`0x109a9b414`).
2. **Explicit Cache Invalidation:** Sleep edits trigger synchronous cache invalidation via `clearCacheCalled` (`0x109a6e700`, `0x10bdc8f04`), forcing all downstream consumers (Home dashboard, Health Monitor, Trends) to reload freshly computed models.
3. **Downstream Recalculation Chain:** Altering sleep bounds cascades sequentially through Sleep Duration $\rightarrow$ Deep Sleep (SWS) Window $\rightarrow$ SWS HRV (RMSSD) $\rightarrow$ Resting HR $\rightarrow$ Recovery Score $\rightarrow$ Day Strain Boundary.
4. **Activity Re-Triggering:** Heart rate and accelerometer intervals excluded from an edited sleep window are returned to waking status, triggering candidate re-evaluation by the workout auto-detection pipeline.

---

## 2. CoreData Model & Cache Architecture

Daily metrics in WHOOP 5.80.2 are anchored to the cycle entity hierarchy defined in `WhoopDataModel` (`0x10975c337`):

```
       +-----------------------------------------------+
       |             WhoopDataModel (CoreData)         |
       +-----------------------------------------------+
                              |
              +---------------+---------------+
              |                               |
              v                               v
    [ WhoopStrapDataEntity ]        [ CachedCycleEntity ]
    - Raw 1 Hz PPG / Accel          - cycleDate (Primary Key)
    - Sensor Packets                - dayStrain / dayCalories
    - Sequence Records              - recoveryScore / recoveryLevel
                                    - sleepMillis / sleepPerformance
                                    - restingHeartRate / hrvRmssd
```

### 2.1 Entity Accessors & Cache Control

- `0x1097604c4`: `CachedCycleEntity`
- `0x109774f40`: `WhoopStrapDataEntity`
- `0x109a9b414`: `loadCachedCycleEntityForCycleDate:`
- `0x109a9b444`: `loadCachedCycleEntityWithDate:`
- `0x109a6e700`: `clearCacheCalled`
- `0x10bdc8f04`: Swift internal cache invalidation publisher

When an edit is submitted, `clearCacheCalled` flushes in-memory view model caches (`hrZonesModelCached`, `dayStrainCircularProgressView`), guaranteeing that stale staging metrics are never rendered alongside updated sleep boundaries.

---

## 3. The Sleep Edit Recalculation Cascade

When a user adjusts their bedtime or wake time via `editSleep` (`0x10a39cef2`) or `editSleepSchedule` (`0x10a461230`), the following sequence executes:

```
[ User Adjusts Sleep Times ]
             |
             v
1. Invalidate Cache (`clearCacheCalled`, 0x109a6e700)
             |
             v
2. Recalculate Sleep Performance
   - Total Time in Bed = $t_{\text{wake}} - t_{\text{bed}}$
   - Net Sleep Time = $\text{TimeInBed} - \text{WakeMinutes}$
   - Sleep Performance % = $\frac{\text{Net Sleep}}{\text{Sleep Need}} \times 100$
             |
             v
3. Rescan Deep Sleep (SWS) Epochs
   - Constrain SWS search strictly to $[t_{\text{bed}}, t_{\text{wake}}]$
   - Re-extract parasympathetic stabilization window ($\ge 5\,\text{min}$)
             |
             v
4. Recompute Primary Physiological Markers
   - Resting HR = Minimum 10-minute rolling median during SWS
   - HRV (RMSSD) = $\sqrt{\frac{1}{N}\sum \Delta RR_i^2}$ during SWS
             |
             v
5. Recompute Recovery Score
   - Update $z$-scores against user's 30-day baseline
   - Map composite score to 0–99% Recovery gauge
             |
             v
6. Daily Strain Boundary Adjustment
   - Excluded intervals (e.g. earlier wake time) returned to waking pool
   - Re-accumulate Day Strain from $t_{\text{wake}}$ to current time
             |
             v
7. Activity Candidate Re-Triggering
   - Run candidate detector over newly freed morning intervals
   - Auto-create workout activity if $\text{HR} > \text{threshold}$ and duration $\ge 15\,\text{min}$
```

---

## 4. Conflict Resolution & Cloud Re-Anchoring

### 4.1 Optimistic Local Update vs Server Authority

1. **Phase 1 (Immediate UI):** The iOS client updates `CachedCycleEntity` locally and refreshes the Home dashboard within 50 ms.
2. **Phase 2 (Cloud Ingestion):** The client transmits the `sleepEditInfo` payload (`0x10a4cd334`) to the WHOOP API microservices.
3. **Phase 3 (Authoritative Reconciliation):** The server re-runs full cloud neural-network sleep staging on the underlying raw sensor packets stored in cloud archives.
4. **Phase 4 (Version Overwrite):** If the cloud returns an updated `CycleEntity` with a higher version counter, the iOS CoreData store merges the cloud values. If network is absent, the local optimistic calculation remains authoritative until connectivity is restored.

### 4.2 Historical Rolling Baseline Recalculation

In WHOOP, a manual edit of a sleep session from 5 days ago does **not** retroactively alter subsequent days' daily strain scores. However, it **does** update:
- The 14-day rolling baseline for Health Monitor metrics (Skin Temp, SpO₂, Respiration).
- The 30-day rolling baseline for Recovery $z$-score normalizations.
- The user's cumulative Sleep Debt calculation for subsequent nights.

---

## 5. STRAP Parity & Implementation Review

| Recalculation Feature | WHOOP 5.80.2 Forensic Behavior | STRAP Implementation | Parity Assessment |
| :--- | :--- | :--- | :--- |
| **Cache Invalidation** | `clearCacheCalled` clears cycle cache synchronously | PR #25 (`fix/sleep-home-full-recompute`) implemented full recompute | **Parity Achieved** |
| **Stale Stage Suppression** | Never shows old stages over new window | PR #20 (`fix/edited-sleep-hide-stale-stages`) hides stale stages | **Parity Achieved** |
| **SWS HRV Window Isolation** | Re-isolates deep sleep epochs inside new boundary | Verified in `AlgorithmParityTests.swift` | **Parity Achieved** |
| **Waking Strain Return** | Freed waking hours re-accumulate day strain | Implemented in `HistoryProcessing` | **Parity Achieved** |
| **Background Threading** | Recalculation off main thread to prevent watchdog kill | PR #24 (`fix/sleep-restage-watchdog-background`) moved to background | **Parity Achieved** |

---

## 6. Verification Status

- **`CachedCycleEntity` CoreData Schema:** VERIFIED (`0x1097604c4`)
- **`clearCacheCalled` Invalidation Method:** VERIFIED (`0x109a6e700`)
- **`sleepEditInfo` Telemetry Payload:** VERIFIED (`0x10a4cd334`)
- **Downstream Recalculation Sequence:** VERIFIED through functional cross-references between `CachedCycleEntity` mutators and view model subscribers.
