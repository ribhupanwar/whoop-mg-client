# STRAP adoption audit: Woop IPA, NOOP, OpenStrap Edge

## Evidence and boundaries
User-supplied iOS.zip contains Woop-ios-unsigned-4a3ef0e.ipa (SHA-256 3f06fe8b24a36861a92553ea27e9bbe949fabfd8d7d566dc7dbca37894c31c5c), including WoopWidgetsExtension.appex and WhoopProtocol_WhoopProtocol.bundle. Inspected archive member list, embedded JSON and Mach-O string inventory, not a running app. Exact string evidence includes "10 live Home Screen widgets in Liquid Glass or Solid", "Heart Rate Graph", "Guided Breathing", "Resting heart rate alerts", "Measurement system", "Reduce glass transparency", and .woop/.noopbak/.sqlite import descriptions. Names include WoopSportPickerView, WoopWidgetSnapshotBridge, SkinTempFunnelDiagnostic, BehaviorInsights, BackupManifest and WoopBackupMergeReport. Strings establish feature intent, not numerical correctness or rendered layout.

Public cross-reference:
- https://github.com/ryanbr/noop/blob/main/docs/FEATURES.md — stress, guided breathing, mood/metric comparisons, data sources and haptics.
- https://github.com/ryanbr/noop/releases — shared stress trace and number, background compute, widget refresh.
- https://github.com/ryanbr/noop/blob/main/docs/PROTOCOL_SENSORS.md — frame offsets and wake/still/sleep envelope, not sleep stages.
- https://github.com/OpenStrap/edge/blob/main/docs/FEATURES.md — HRV spot-check, breathing coherence, workout, guides, local backup and idempotent HealthKit exports.
- https://github.com/OpenStrap/analytics — independent published-method analytics.

No executable, decompiled source, proprietary artwork, fonts or third-party implementation is imported. Preserve STRAP's own source and licenses. Public documentation is feature evidence, not proof of physical accuracy.

## Adoption matrix
| Area | STRAP evidence/status | Decision |
|---|---|---|
| Gen5 BLE, history ACK, archive/replay, reconnect | BandLink, V18Record, HistoryDatabase; previous cross-repository reliability audit | Preserve; device regressions only. No unverified firmware commands. |
| Skin temperature | NightTemperature, HealthMonitor; #284 adds per-gate export | High priority physical replay; preserve candidate status and absolute/deviation separation. |
| Oxygen | V18 byte 74 candidate, #284 malformed replay fix | Calibration missing; do not expose as measured or infer red/IR mapping. |
| Respiration | Respiration.swift and whoop/health.py | This PR aligns replay selection and motion/missing-beat boundaries; no change to RSA estimator or claimed accuracy. |
| Stress | StressWindows and BandLink; #285 gap-aware windows and UI | High priority: one fresh motion-aware producer for Home/Health/detail/widget, timestamp and coverage, raw deviation, cached off-main processing; validate against own overnight/daytime capture. Do not adopt a new curve solely to avoid zero. |
| Recovery/HRV/RHR/sleep/strain | Existing own analytics | Preserve algorithm until paired evidence proves improvement; compare shadow estimators, not overwrite scores. |
| Start Activity | GPSRunView, WorkoutRecorder; #285 indoor/GPS and render-sampling fixes | Device verify picker, map location permission, GPS off, indoor/outdoor, pause, resume, save, Live Activity and accurate HR sample identity. |
| Sleep, nap edit | SleepCoach, SleepSession and correction path | Validate independent nap detection/edit/debt and preserve primary-night recovery. |
| More / tabs / theme | #285 links, appearance preferences, optional glass | Native visual verification; keep four tabs and private local records. |
| Widgets | Main has captured steps and workout/steps Live Activities; #285 adds opt-in daily health widget | Extend separate single-metric widgets and timestamped HR/stress graphs only after app-group signing/refresh tests; do not claim actual free-ID support. |
| Journal behavior comparisons | #285 explicit answered-day sleep comparison | Add next-day alignment, HRV/RHR/recovery associations with sample size and no causal claims; validate journal semantics. |
| Guided breathing / HRV spot-check | LiveSessionView / Hrv provide partial foundation; no guided feature found | Useful clean-room addition: optional slow comfortable visual pacer, valid RR coverage, before/after RMSSD, no score modification. Haptics only under session ownership and proven protocol. |
| Portable backup | StrapBackup validates own manifest, WHOOP CSV import exists | High value: format-specific read-only staging and schema mapping for .woop/.noopbak/.sqlite; obtain representative archive, validate schema, dedup, rollback, provenance. Never weaken current restore whitelist or copy credentials. |
| Alerts / emergency | WakeAlarm and local notification UI | Optional resting HR trend notification only after verified data, explicit consent/cooldown; no auto emergency dispatch or clinical claim. |
| Units and display | Metric-only copy in preferences | Add display conversion separately; never mutate stored SI values. |
| HealthKit | Existing integration | Test source ownership and idempotence; never export unvalidated SpO2 or scores as medical readings. |
| Training intervals, Siri, guides | Existing haptics and workout recorder; guided flow not verified | Secondary scope after accuracy; prefer explicit controls and no background guarantees. |
| Nutrition, cloud accounts, other bands, social | Not necessary for personal Gen5 client | Do not add merely for feature count. Optional local nutrition later; no cloud or firmware scope creep. |

## Release gates
PR #284 and #285 are separate active work. This branch changes only respiration and audit documentation, without duplicating their files. The legacy sleep research PR #211 is not a release dependency. Exact-head six protocol checks, native iOS build/test/IPA and review are required. Hardware evidence: paired overnight RR/temperature/oxygen candidates, awake motion and stress trace, fresh/stale transitions, real workout and signed-widget tests. No complete feature parity or pixel accuracy can be certified from static inspection. Further feature candidates are not represented as implemented.
