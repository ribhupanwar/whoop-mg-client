# STRAP ↔ Woop Deep Component Adoption — Comparison Matrix (V2)

**Date:** 2026-11-27
**Branch:** `feat/woop-deep-adoption-20261127` (off `origin/main` @ `96c1711`)
**Reference:** `iOS.zip` → `Woop-ios-unsigned-4a3ef0e.ipa` (decrypted, 76 MB ARM64 Mach-O `Woop`)
**Method:** Static symbol/string forensics on the actual decrypted executable + `Assets.car` + `WhoopProtocol.bundle/whoop_protocol.json`, cross-checked against STRAP production source. Symbol presence is treated as *evidence of a code path*, never as proof of thresholds or calibration.

> Licensing: no proprietary WHOOP/Woop artwork, code, or coefficients are copied. Woop is an engineering reference only. All STRAP changes are independent, local-only, MIT.

## 1. Reference identification

| Item | Value |
|---|---|
| Archive | `C:\Users\ribhu\Downloads\iOS.zip` (62,967,587 bytes) |
| Contents | `Woop-ios-unsigned-4a3ef0e.ipa`, `Woop-iOS-Install-Guide.pdf` |
| Executable | `Payload/Woop.app/Woop` (76,307,072 bytes, decrypted Mach-O) |
| Embedded plugin | `WoopWidgetsExtension.appex` |
| Bundles | `WhoopProtocol_WhoopProtocol.bundle/whoop_protocol.json`, `GRDB`, `ZIPFoundation` |
| Fonts | `woop_proxima_{regular,semibold,bold}.otf`, `woop_dinpro_{medium,bold}.otf`, `InterVariable.ttf` |
| Asset catalog | `Assets.car` (2,302,808 bytes) — 171 asset tokens recovered |
| Protocol | `whoop_protocol.json` v1 — full PacketType/EventNumber/CommandNumber enums + V24/V12/V5 record layouts |

### Woop symbol confirmation (count in decrypted Mach-O)

All 26 named components exist in the binary (evidence, not semantics):
`SleepStager` 2858, `PreSleepHeartRateFeedback` 419, `HrvWindow` 286, `REMFunnelDiagnostic` 48, `HypnogramMetrics` 45, `Spo2ReTrace` 40, `respRateFromRR` 29, `SkinTempBackfill` 99, `SkinTempDisplay` 89, `FitnessAgeEngine` 105, `WoopFitnessAgeData` 31, `nightlySpo2CandidateMean` 8, `nightlySpo2RawMeans` 7, `adaptiveBaselineFloor` 5, `morningStillnessWindowMin` 5, `withoutCalibratedSpo2` 5, `fitnessAge{CollapsedBarHeight,CompactOrb,Halo,LegendDividerHeight,PaceRailHeight}` 5 each, `applySleepEdit` 10, `hrSleepBaselineMult` 1, `aux1Raw` 11, `aux2Raw` 5.

## 2. Component-by-component matrix

Legend: ✅ Already correct · 🟡 Present, improvable · ➕ Missing & suitable · ❓ Needs evidence · ⛔ Incompatible · © License-restricted

| # | Component | Woop evidence | STRAP status | Verdict |
|---|---|---|---|---|
| **Sleep** |
| 1 | Sleep onset (HR drop + baseline + motion + band state) | SleepStager, adaptiveBaselineFloor, hrSleepBaselineMult | `SleepDetect.detect` autonomic onset gate, HR-transition splitter, band-state trim, sparse-gravity, off-wrist backstop | ✅ |
| 2 | Morning stillness / wake confirmation | morningStillnessWindowMin | terminal HR+motion transition (elev≥240,moving≥90), sustained up(3) trim, terminalUp corroboration | ✅ |
| 3 | Bathroom interruption merge | (splice handling) | `mergeNocturnalPeriods` 30-min + confirmed 45-min extended resumption | ✅ |
| 4 | Adaptive personal baseline | adaptiveBaselineFloor | activeMedian dual-band (hrSleepBaselineMult/quiescent) — *not* multi-night EWMA | 🟡 |
| 5 | Pre-sleep HR feedback | PreSleepHeartRateFeedback (419) | `PreSleep*` refs present (4) | 🟡 verify coverage |
| 6 | Hypnogram metrics | HypnogramMetrics | `Hypnogram` present (8) | ✅ |
| 7 | Sleep edit authority | applySleepEdit | manual edits authoritative + recalc | ✅ |
| 8 | REM funnel diagnostic | REMFunnelDiagnostic | `StageDecisionEvidence` decision trace (per-epoch) | 🟡 (different shape) |
| 9 | HrvWindow 5-min | HrvWindow | `Hrv` five-minute windows + evidence export (PR #290) | ✅ |
| **Respiration** |
| 10 | RR→resp (respRateFromRR) | respRateFromRR (29) | `Respiration.swift` spectral + consensus + coverage gates (PR #286/#294) | ✅ |
| 11 | Respiratory diagnostics export | — | eligible/accepted/rejected windows exported | ✅ |
| **SpO₂** |
| 12 | Candidate mean/nightly aggregation | nightlySpo2CandidateMean, nightlySpo2RawMeans | tri-mode candidate @ inner[74], nightly median, unverified label (PR #284/#294) | ✅ |
| 13 | Re-trace / withoutCalibrated | Spo2ReTrace, withoutCalibratedSpo2 | candidate kept separate from calibrated; no fabricated % | ✅ |
| **Temperature** |
| 14 | Skin temp backfill/display | SkinTempBackfill, SkinTempDisplay, aux1Raw/aux2Raw | `NightTemperature` + aux1/aux2 decode + sentinel reject (PR #299 open) | 🟡 |
| **HRV/RHR/Recovery/Strain** |
| 15 | HRV SWS-gated RMSSD | — | Task-Force 20% + ectopic + SWS gate — superior | ✅ |
| 16 | RHR / Recovery / Strain | — | Recovery V2, monotonic strain, live strain | ✅ |
| **Healthspan** |
| 17 | Animated orb (organic morph) | fitnessAgeCompactOrb, Halo | `HealthspanParticleField` organic membrane + particles, reduce-motion/low-power | ✅ |
| 18 | Pace of Aging rail | fitnessAgePaceRailHeight | `paceCard` "Pending validation" (no fabricated value) | ✅ (correct state) |
| 19 | 9 contributors | WoopFitnessAgeData | all 9 in `HealthspanInsights` w/ coverage, prior, source | ✅ |
| 20 | 180-day history option | FitnessAgeEngine | 6-month charts present | 🟡 verify 180d toggle |
| **Icons** |
| 21 | Custom icon set | Drawable*/Glyph* (171) | `StrapIconRegistry` + 29 imagesets + clean-room vectors | 🟡 (SF-symbol heavy) |
| **Protocol / sensor** |
| 22 | Optical source telemetry | — | `irSourceSelected`/`hrQualityCounter` NOT split from inner[28] | ❓ offset conflict (doc says inner[20], prod verified inner[28]) |
| 23 | GET_DATA_RANGE / stuck detector | — | implemented (DataRangeResponse, StuckStrapDetector) | ✅ |

## 3. Genuinely missing / improvable (safe to adopt)

1. **Optical source telemetry split** (❓) — blocked on offset reconciliation: deep-comparison doc cites `inner[20]`, but production `V18Record` decodes `hrQualityFlags` at `inner[28]` validated on 32,663 real captures. Moving it would regress. **Action:** add derived bitfield accessors on the *existing* inner[28] value (non-destructive, no offset change) + Python parity + tests. Classified IMPLEMENTED-DEVICE-VALIDATION-REQUIRED.
2. **Multi-night adaptive sleep baseline (EWMA)** (🟡) — additive, behind coverage floor, no fixed universal HR threshold. IMPLEMENTED-DEVICE-VALIDATION-REQUIRED.
3. **Icon optical fidelity** (🟡) — SF Symbols dominate; add clean-room vectors for the highest-value reference-specific glyphs (sleep moon, bedtime/waketime, metric HRV/RHR, oxygen, fitness-age). IMPLEMENTED.
4. **180-day Healthspan history toggle** (🟡) — verify/extend display window with real coverage only.

## 4. Explicitly NOT done (with reason)

- No proprietary WHOOP classifier coefficients, recovery weights, or Pace-of-Aging formula invented. ©/❓
- No raw-ADC→SpO₂% calibration (no verified wavelength mapping). ⛔
- No universal fixed HR thresholds replacing personal baselines. ⛔
- No merge of unrelated naps / no backward extension on stillness alone. ⛔
- No duplication of merged PRs (#284/#286/#290/#292/#294/#300/#301).