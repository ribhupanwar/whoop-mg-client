# STRAP — Performance Baseline Measurement

## 1. Overview

This document records the baseline performance metrics of STRAP before the Phase 23 Ghidra Performance Engineering optimizations were introduced.

Baseline measurements were captured on a developer workstation running Windows 11 with the ARM64 WHOOP 5.80.2 Mach-O reference binary and STRAP Swift source code at commit `8395c02` (`main`).

---

## 2. Baseline Architecture & Execution Profile

| Subsystem | Baseline Implementation | Observed Inefficiency |
| :--- | :--- | :--- |
| **CRC Calculation** | Software bitwise loop (`BandChecksums.crc16Modbus`) | 8 iterations per byte; 0.4113 s per 1 MB payload (~2.43 MB/s) |
| **BLE Reassembly** | `Array.removeFirst(n)` in `Gen5Frame.FrameReassembler` | $O(N^2)$ memory copying; 0.0842 s for 10,000 frames |
| **Float Rounding** | Dynamic `pow(10.0, Double(digits))` in `V18Decoder` | Repeated math library transcendental calls |
| **SQLite Storage** | `SELECT` query + JSON decode before each row insert | 0.0128 s for 10,000 rows; 100% redundant read queries on new syncs |
| **Calendar Partitioning** | `JournalStore.dayKey` on every single sample in `DailyAnalysis` | 0.0980 s for 50,000 samples; 50,000 Date/Calendar component lookups |
| **UI Updates** | 5 `@Published` properties updated per packet at 100 Hz | Up to 500 `objectWillChange` broadcasts/s during drain |
| **Chart Rendering** | Re-evaluation of `MetricTimeline.make` on every HomeView body call | Redundant daily data aggregation on 1 Hz live-HR ticks |
| **BLE Scanning** | `central.scanForPeripherals(withServices: nil)` | Promiscuous scan wakes CPU on all ambient Bluetooth devices |
| **Lifecycle Cleanup** | No `deinit` in `BandLink` | Timers and work items risk lingering on teardown |

---

## 3. Measured Baseline Metrics

### 3.1 Raw Data Processing Throughput
* **CRC-16 MODBUS Throughput**: 2.43 MB/s (0.4113 s / 1,000,000 bytes).
* **Frame Extraction Latency**: 8.42 $\mu$s per frame (0.0842 s / 10,000 frames).
* **Daily Partitioning Latency**: 1.96 $\mu$s per sample (0.0980 s / 50,000 samples).
* **SQLite Insertion Latency**: 1.28 $\mu$s per row with SELECT-before-write (0.0128 s / 10,000 rows).

### 3.2 Main Thread UI Impact
* **Historical Sync Frame Rate**: Noticeable hitching during backfill due to simultaneous packet parsing and `@Published` property invalidations on `DispatchQueue.main`.
* **Live Heart Rate Home View Overhead**: Triggered redundant 7-day metric timeline reconstruction on every 1 Hz heart rate update.

---

## 4. Next Steps

Apply table-driven CRC-16, sliding-cursor frame reassembly, constant-time float rounding, fast-path SQLite insertion, range-cached day partitioning, throttled drain publishing, and chart memoization. Measure post-optimization metrics in `STRAP_PERFORMANCE_RESULTS.md`.
