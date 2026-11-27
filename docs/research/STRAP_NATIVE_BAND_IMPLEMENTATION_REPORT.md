# STRAP — Native Band Utilization Implementation Report

**Date:** 2026-11-27  
**Baseline:** `main` @ `3ee32be` (reconciled against `a89c451`, PR #311, PR #312, PR #296, and the three `kilo-test` reports)  
**Engineering Mode:** Band First — Native Data First — Algorithm Tuning Last

---

## 1. Reconciliation Against Active `main` & PRs

Before implementing changes, the three `kilo-test` reports (`STRAP_GHIDRA_DEEP_ACCURACY_REPORT.md`, `STRAP_NATIVE_BAND_METRICS_REPORT.md`, `STRAP_FULL_BAND_CAPABILITY_MATRIX.md`) were reconciled against `main` (`3ee32be`) and active PRs:

| Finding in Reports | Actual State on `main` / PRs | Action Taken |
|---|---|---|
| Skin temp `-5000` sentinel missing | **Already implemented** in `3e9fcb5` (PR #299, `V18Record.swift`) | Added explicit `-5000` regression test in `NativeBandUtilizationTests` |
| Workout Live Activity driven by `GPSRunView` timer | **Already moved** to `WorkoutLiveActivityCoordinator` (`7dec673`, PR #302; `3ee32be`, PR #311) | Preserved; no duplication |
| Sleep lifecycle (`#160`) missing | `SleepLifecyclePhase`/`Persistence` on `main` (`a89c451`); UI/AppStore wiring in **PR #312** | Coordinated with PR #312; avoided touching `AppStore.swift`, `HomeView.swift`, `StressView.swift` |
| `heartKeyHRV` in R17 ECG ignored | Ghidra `5.78` (`0x109658590`) & `MGEcgPacket.swift` do **not** pin byte offset/scale/units | Kept RR-derived RMSSD (`Hrv.swift`); documented as hardware-blocked |
| Command response results (`0x24`/`0x26`) mostly ignored | Only `0x22` and `0x1D` handled in `BandLink.swift` | Implemented `BandCommandResult` for all command responses |
| Wrist contact bits, pSNR (`-128`), cadence unexposed | Decoded in `WhoopStatusPacket`/`V18Sample`, no live/diagnostic consumer | Implemented `NativeSensorSnapshot` + `HealthView` diagnostics |
| No `BGProcessingTask` background history sync | Only foreground timers + CoreBluetooth state restoration | Implemented `BackgroundSyncScheduler` (`com.ribhupanwar.strap.history-sync`) |

---

## 2. Capability Before & After

| Capability | Before (`3ee32be`) | After (this PR) |
|---|---|---|
| **Command Responses (`0x24`/`0x26`)** | Only `getDataRange` (`0x22`) and `rebootStrap` (`0x1D`) inspected | All `0x24`/`0x26` responses decoded via `BandCommandResult` (`commandOpcode`, `originSequence`, `resultCode`, `isSuccess`), published on `BandLink`, and logged |
| **Wrist Contact Bitfield** | `WhoopStatusPacket` decoded `wristStateRaw` (`0x0001`/`0x0002`/`0x0004`), discarded bit detail | `NativeSensorSnapshot` preserves `capacitiveTouch`, `opticalReflectance`, `onBodyPlacement` with timestamp & `isFresh(at:)` |
| **Optical Signal Quality (`pSNR`, `logVar`)** | Stored in `V18Sample` BLOB only; not surfaced | Surfaced in `NativeSensorSnapshot` & `HealthView` diagnostics; `-128` explicitly treated as **unavailable**, never low quality |
| **Native Cadence (`stepCadence`)** | Stored in `V18Sample` BLOB; consumed only in `Activities.swift` | Validated (`0...250` spm) and surfaced with freshness gating in `NativeSensorSnapshot` & `HealthView` |
| **Background History Sync** | CoreBluetooth state restoration + foreground timers only | Added opportunistic `BGProcessingTask` (`BackgroundSyncScheduler`, `com.ribhupanwar.strap.history-sync`) + `processing` background mode |

---

## 3. Native Packet Evidence

- **GATT Service `FD4B0001-CCE1-4033-93CE-002D5875F58A`:**
  - `FD4B0003` (`0x24` / `0x26` command responses): `inner[0]` type, `inner[1]` response seq, `inner[2]` command opcode, `inner[3]` origin seq, `inner[4]` result (`0x01` = success, `0x00` = failure).
  - `FD4B0004` (`0x30` hardware/status events): `WhoopStatusPacket` (`inner[2] == 0x03`, `inner[13..14]` SoC tenths %, `inner[15]` charging bit 0, `inner[16..17]` `wristState` bitfield: bit 0 capacitive, bit 1 optical, bit 2 placement).
  - `FD4B0005` (`0x2F` V18 historical): `inner[49..50]` u16 step counter, `inner[51]` u8 cadence (0–250 spm), `inner[55]` u8 `activityClass`, `inner[65..66]` i16 skin temp ÷100 (`-5000` = `-50.00 °C` unavailable sentinel), `inner[73]` sleep state byte, `inner[74]` SpO₂ candidate byte, `inner[100]` `psnrB` i8 (`-128` unavailable), `inner[101]` `psnrA` i8 (`-128` unavailable), `inner[105..108]` f32 `signalQualityLogVariance`.

---

## 4. Production Files Modified / Added

- `ios/Strap/Protocol/BandCommandResult.swift` (new) — decodes all `0x24`/`0x26` command response frames.
- `ios/Strap/Analysis/NativeSensorSnapshot.swift` (new) — timestamped, freshness-gated native contact, pSNR, cadence, and optical quality snapshot.
- `ios/Strap/Band/BackgroundSyncScheduler.swift` (new) — `BGTaskScheduler` registration and opportunistic `BGProcessingTask` scheduling.
- `ios/Strap/Band/BandLink.swift` — publishes `lastCommandResponse`, `commandFailureCount`, `nativeSensorSnapshot`, and wires `BackgroundSyncScheduler`.
- `ios/Strap/StrapApp.swift` — registers `BackgroundSyncScheduler` at launch.
- `ios/Strap/HealthView.swift` — displays native sensor quality, contact bitfield, pSNR (`unavailable` for `-128`), cadence, and command ACK/NACK in `rrDiagnosticPanel`.
- `ios/project.yml` — adds `processing` background mode and `BGTaskSchedulerPermittedIdentifiers`.
- `ios/StrapTests/NativeBandUtilizationTests.swift` (new) — regression tests for all new decoders, sentinels, and `BGProcessingTask` request config.

---

## 5. Explicitly Unsupported / Hardware-Blocked Capabilities

- **`heartKeyHRV` (R17 ECG `0x2B` / `0x2F`):** Present in WHOOP 5.78/5.80.2 string tables (`FilteredECGPacketParsingError.HeartKeyHRVFailedToParse`), restricted to MG models (`MGEcgPacket.isMG`), and byte offset/length/scale are **not** pinned in Ghidra or captured fixtures. STRAP retains RR-derived RMSSD (`Hrv.swift`).
- **Calibrated SpO₂ % & Native Respiratory Rate:** Server-side in WHOOP (`oxygen-saturation-upload`, `respiratory_rate_samples`). STRAP retains candidate-only SpO₂ (`70–100` / `0x80` saturated) and local RSA-from-RR (`Respiration.swift`).
- **Server-Side Recovery, Stress (0–3), Healthspan:** Computed on WHOOP backend BFF/GET endpoints; STRAP retains independent local estimators.
- **Force-Quit Background Execution:** iOS does not wake user force-quit apps; `BGProcessingTask` is opportunistic and OS-scheduled.

---

## 6. Remaining Hardware-Validation Requirements

1. Capture a real WHOOP MG R17 (`0x2B`) packet to pin `heartKeyHRV` byte offset, scale, and validity flags.
2. Capture a v10 V18 session to verify live on-wrist vs off-wrist `WhoopStatusPacket` transitions, `psnrA`/`psnrB` dynamics, `stepCadence`, and skin temp `-5000` sentinel on hardware.
3. Verify opportunistic `BGProcessingTask` execution and CoreBluetooth state restoration on a SideStore-signed physical iPhone.
