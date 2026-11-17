# WHOOP 5.78.0 Calorie Engine — Engineering Handoff

**Date:** 2026-11-17  
**Target:** `ribhupanwar/whoop-mg-client`, branch `main`  
**Status:** Mathematical heart-rate calorie path substantially recovered from user-supplied Ghidra ARM64/decompiler excerpts. **Research only; production calculator unchanged.**  
**Companion:** [WHOOP_CALORIE_BINARY_FINDINGS.md](WHOOP_CALORIE_BINARY_FINDINGS.md)

## Executive summary

We located the WHOOP iOS 5.78.0 resting metabolic rate, workout HR rate, threshold-based interpolation, timestamp-duration calculation, and per-sample calorie integration. A misleading Ghidra decompilation was resolved by checking ARM64: the interpolation helper returns two floating-point registers, `d0=slope` and `d1=intercept`, and its caller computes `intercept+slope*HR`. Do **not** claim exact WHOOP calorie parity until active-vs-total mapping, sample boundaries, and real workout comparisons are tested.

## Verified / recovered functions

| Address | Meaning | Evidence |
|---|---|---|
| `1002180e0` | Resting kcal/s, revised Harris–Benedict | Decompiled arithmetic |
| `100218490` | Workout HR-based rate | Decompiled arithmetic; wrapper `100218550` |
| `100217ef8` | HR-reserve threshold and rate × duration integration | Decompiled path and ARM64 caller |
| `1002181ec` | Two-register linear interpolation coefficients | ARM64 `d0` slope, `d1` intercept |
| `1001f0480` | Timestamp interval array | Decompiled loop and ARM64 append branch |
| `1000eb7d0` / `1000ec4a0` | Array last-element retrieval | ARM64/decompiler |

### Resting rate

Inputs inferred: weight kg (`w`), height **meters** (`h`), age years (`a`), baseline enum (`b`).

- `maleRate=max(0, 88.362 + 13.397*w + 479.9*h - 5.677*a)/86400`
- `femaleRate=max(0, 447.593 + 9.247*w + 309.8*h - 4.33*a)/86400`
- `b=0` selects first; `b=1` second; `b=2` their mean. Exact semantic enum mapping still needs metadata confirmation.

### Workout rate

Let `hrCapped=min(hr,maxHR)`:

- `rate0=max(0, 0.2*a + 0.19*w + 0.6*hrCapped - 50)/251.04`
- `rate1=max(0, 0.07*a - 0.13*w + 0.4*hrCapped - 15)/251.04`
- Baseline `0` selects rate0, `1` rate1; other values use their mean in this helper.

### HR-based integrated energy

Threshold `T = restingHR + 0.30*(maxHR-restingHR)`.

The interpolation helper constructs:
- `slope=(referenceRate-restingRate)/(maxHR-T)`
- `intercept=restingRate-T*slope`

For each valid HR sample and duration:
- if `HR < T`, `rate=restingRate`;
- otherwise `rate=intercept+slope*HR`;
- `sampleEnergy=rate*durationSeconds`;
- total is the sum of sample energies.

**ARM64 proof (critical):** `100217fd8 bl FUN_1002181ec`; `100217fdc mov v10.16B,v0.16B`; `100217fe0 mov v11.16B,v1.16B`; `100218014 fcmp d0,d9`; `100218018 b.pl 10021802c`; below-threshold `100218024 mov v13.16B,v8.16B`; above-threshold `10021802c fmul d0,d10,d0`, `100218030 fadd d13,d11,d0`; `100218060 fmul d0,d13,d12`. This disproves Ghidra's earlier scalar-return interpretation.

### Timestamp durations

`FUN_1001f0480` calculates consecutive time intervals, capping at **3 seconds**. A particular count-mismatch branch repeats the final existing interval: `1001f0718 bl FUN_1000eb7d0`; `1001f0728 mov x20,x0`; `1001f0774 str x20,[x8,#0x20]`. Verify singleton, empty, missing-next-timestamp, out-of-order and duplicate cases before claiming full equivalence. Avoid silently filling long BLE gaps.

## Existing STRAP production differences

Inspected `ios/Strap/Analysis/Calories.swift` and `ios/StrapTests/CaloriesTests.swift` on `main`:

- Current basal: Mifflin–St Jeor; recovered WHOOP path: revised Harris–Benedict.
- Current HR reserve gate: **40%**; recovered path: **30%**.
- Current timestamp gap cap: **30 s**; recovered path: **3 s**.
- Current `activeKcalTimestamped` estimates **active** energy and subtracts basal; recovered integrated path appears to include resting rate under threshold. Do not compare these values as though they have the same semantics.
- Current session path has cadence/MET fallback; no equivalence established with the recovered binary path.

## Implementation plan (safe, incremental)

1. Create a **separate, experimental** Swift calculator, e.g. `ios/Strap/Analysis/WhoopRecoveredCalories.swift`, without modifying production `Calories` or any call sites. Include explicit input validation and documented output semantics; do not manufacture missing profile/HR data.
2. Add `WhoopRecoveredCaloriesTests.swift`: resting rates for both baselines, baseline mean, capped maxHR, threshold equality, below/above threshold, interval 3-second cap, last-sample branch, invalid/missing/duplicate/out-of-order samples, non-finite values, and sum-of-interval energy.
3. Verify remaining assembly edge cases and exact physiological-baseline enum metadata. Determine whether the binary uses a workout-specific calculation or the integrated daily calculation at each call site.
4. Compare against **actual WHOOP exports/screenshots** with matched timestamps, body profile, RHR/maxHR and workout type. Record separate active and total kcal, percentage error, and error causes.
5. Only after verified comparisons and passing GitHub Actions should an opt-in feature flag or production replacement be considered. Preserve historical data, licensed fonts and existing metrics.

## Completion criteria

- [x] Identify resting and workout equations.
- [x] Identify 30% HR reserve threshold.
- [x] Verify slope/intercept registers and HR interpolation using ARM64.
- [x] Identify interval cap and last-element append branch.
- [ ] Resolve interval edge cases and physiological enum semantics.
- [ ] Implement isolated Swift calculator and deterministic tests.
- [ ] Run iOS CI and fix any new build/test errors.
- [ ] Validate real WHOOP workouts and active-vs-total semantics.
- [ ] Decide production integration only after evidence.

**Do not mark calorie parity complete or replace the current calculator solely from these excerpts.**
