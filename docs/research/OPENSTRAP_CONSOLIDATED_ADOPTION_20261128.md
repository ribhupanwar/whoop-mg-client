# Consolidated OpenStrap adoption — 2026-11-28

Base STRAP main: 3d3d5d01f71453912b3efb37c500289976a748ed (#324).
Pinned upstream: [Edge f6faa239](https://github.com/OpenStrap/edge/tree/f6faa2390376a2dc27db01fa8586dee42b264462), [Analytics a438df40](https://github.com/OpenStrap/analytics/tree/a438df40b38a4586a52a68ab7e1c100fca111ccd), [Protocol dc699ce4](https://github.com/OpenStrap/protocol/tree/dc699ce491c5eec4c924fafe8e29c637ea758b5a).
Independent implementation from mathematical descriptions and reviewed interfaces; no upstream source or firmware binaries copied.

| Area | Existing evidence / scope | Disposition |
|---|---|---|
| Respiratory rate | Respiration.swift already implements resampled spectral and peak-train consensus; upstream resp_rate.dart uses irregular-time harmonic spectrum | Implemented separate diagnostic spectral alternative; optional field in explicit recovery diagnostic export; not a replacement |
| RSA + optical | OpticalRRFusionEvidence and Gen5V26Record.swift already implement guarded research fusion | Keep; validate aligned windows and real optical samples, no duplicate |
| Wrist-angle, staging | #324 canonical sleep reconciliation, existing WristAngleInactivityExperiment, #329 offline wrist-angle/local-HR evidence | Continue #329, do not replace the protected sleep logic before paired-night replay |
| Step calibration | Edge lib/data/step_calibration.dart and lib/compute/step_calibration_fit.dart | Implemented isolated controlled-walk factor, no daily ledger or workout count changes; requires explicitly counted test walks |
| Sleep regularity | Current SleepReport uses bedtime/wake tolerance; upstream uses paired daily epochs | Implemented coverage-aware paired-day index research function; actual full-day observed epoch input and DST-aware alignment pending |
| Smart wake | Edge lib/state/smart_wake.dart retains on-band fallback alarm; current STRAP alarm confirmation already exists | Defer real alarm behavior until causal wake evidence, time-window/foreground/background and hardware tests pass; never cancel fixed fallback |
| Workout termination recovery | Edge lib/state/workout_controller.dart persists active state; STRAP WorkoutRecorder retains active accumulators in memory | Separate coordinated follow-up after #327; persist active session identity, pause intervals, last sample timestamps and route/energy accumulators; prevent discarded session resurrection |
| Firmware | #328 local image lab | Remains disabled for hardware installation pending authenticated image, hardware compatibility and recovery validation |
| Live steps | #327 live IMU/Dynamic Island | Already active; no competing changes |
| Temperature and oxygen | Existing device-specific candidates, V20/V22/V26 research; calibration still unresolved | No unverified absolute units or coefficients; compare decoded sensor provenance and real simultaneous readings, not fit to one vendor value |
| Circadian analysis | Upstream observed multi-day rhythm and body clock metrics | Deferred pending sufficient full-day epoch coverage |
| HRV/RHR/Recovery | Owner reports first exact HRV/RHR match on Nov 28; #326 freeze | Do not alter accepted computation or archive selection |

## Diagnostic limits and acceptance

Spectral RSA here uses cumulative RR timing in existing contiguous segments; this is NOT native beat timestamp recovery and not exact upstream Lomb–Scargle parity. The peak and confidence gates are provisional and must be calibrated on independent data. Count all complete 5-minute windows, including missing ones. Compare against current production and reference respiratory estimates on multiple nights; include noise, flat signals, aliasing, motion, replay, ectopy and absent signal. No production metric changes without improvement and approval.

Step calibration and regularity are isolated candidates, not enabled UI features. For regularity supply correctly aligned consecutive local days with observed sleep/awake epochs (not missing = awake); DST/offset changes must abstain. For controlled step calibration verify same device/placement, independent walks, known manual counts, and repeatable factor. Preserve raw counts and never silently apply correction.

Existing #324 timing and stage logic remain unchanged. For sleep adoption require multi-night onset/final wake absolute error, TST/WASO, epoch alignment/confusion matrix (reference WHOOP is not PSG), morning bathroom return, awake-in-bed, stale history, and manual override tests. Targets onset/wake within 2 minutes; evaluate stage error separately. Private captures remain off Git. #327 shares BandLink.swift; check current-head integration and required freeze review before merge. Native CI not yet verified.
