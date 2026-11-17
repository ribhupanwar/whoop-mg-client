# WHOOP 5.78.0 ARM64 calorie reverse-engineering findings

Status: **research reference only; not enabled in production**. Based on Ghidra excerpts supplied by the app owner on 2026-11-17. This does not establish exact parity with every WHOOP energy display.

## Recovered symbols

- `FUN_1002180e0`: resting metabolic rate in kcal/second. Inputs inferred: weightKg, heightMeters, physiological baseline, ageYears. Revised Harris–Benedict coefficients:
  - baseline 0: `max(0, 88.362 + 13.397*weightKg + 479.9*heightMeters - 5.677*ageYears)/86400`
  - baseline 1: `max(0, 447.593 + 9.247*weightKg + 309.8*heightMeters - 4.33*ageYears)/86400`
  - baseline 2: mean of the two clamped rates.
- `FUN_100218490`: workout HR-based energy rate; wrapper at `100218550`. Inputs: weightKg, bpm, maxHR, baseline, ageYears. HR is capped to maxHR. Baseline 0: `max(0, 0.2*age + 0.19*weight + 0.6*min(bpm,maxHR) - 50)/251.04`. Baseline 1: `max(0, 0.07*age - 0.13*weight + 0.4*min(bpm,maxHR) - 15)/251.04`. Other baseline values averaged by this helper.
- `FUN_100217ef8`: HR sample integration; threshold `restingHR + 0.3*(maxHR-restingHR)`; below threshold resting rate, above threshold interpolated HR rate; sum(rate*sampleInterval).
- `FUN_1002181ec`: interpolation helper. ARM64 returns **two doubles**, `d0 = slope` and `d1 = intercept`, calculated as `slope=(referenceRate-restingRate)/(maxHR-threshold)` and `intercept=restingRate-threshold*slope`. Ghidra's one-double decompilation of the caller is **not reliable**. Inspect caller ARM64 near `100217fd8` before coding this branch.
- `FUN_1001f0480`: timestamp interval construction. Consecutive intervals capped to 3.0 seconds. At `1001f0718` it calls `FUN_1000eb7d0` for the last element; `1001f0774` appends that element when the branch's count check requires it. Not all edge cases established.
- `FUN_1000ec4a0`: indexed 8-byte array element load.

## Current STRAP differences (main at inspection)

`ios/Strap/Analysis/Calories.swift` uses Mifflin–St Jeor BMR, a 40% HR-reserve gate, and default 30-second timestamp gap cap. Those differ from this binary path. The existing model should **not** be silently replaced: it returns active calories, whereas the reverse-engineered integrated path may include resting energy. Validate units, baseline enum mapping, sample-end behavior, HR data quality, and real workout comparisons first.

## Safe integration checklist

1. Verify the `FUN_100217ef8` ARM64 call/return register usage (`d0` slope, `d1` intercept).
2. Add an isolated experimental Swift model with no production call sites; add deterministic unit tests and edge cases.
3. Compare the experimental output with user-provided WHOOP workouts and time windows; distinguish active vs total kcal.
4. Only after passing comparison and CI, consider an opt-in implementation change. Never fabricate missing profile or HR data.
