# WHOOP binary calorie and RHR findings — 2026-11-15

Source: user-provided Ghidra exports WHOOP_FUNCTION_BATCH.json, WHOOP_BATCH4.json, WHOOP_BATCH5.json, WHOOP_BATCH6.json, WHOOP_BATCH7_CONSTANTS.json. Static reverse-engineering observations only; no claim of runtime equivalence.

## Resting calories
Function 0x1002163b4 (called by calculateRestingCaloriesWithPhysiologicalBaseline:weightInKilograms:heightInMeters:age:, 0x100216748):
A=max(0, 13.397*x + 479.9*y - 5.677*z + 88.362)
B=max(0, 9.247*x + 309.8*y - 4.33*z + 447.593)
category 0 selects A; 1 selects B; 2 averages A and B; other values hit error path.
Return selected / 86400.0 (DAT_108a7b098). Coefficients match revised Harris-Benedict BMR equations with x=weight kg, y=height meters, z=age years; validate Swift/ARM64 parameter mapping before implementation.

## Workout calories
Function 0x100216764 (called by calculateWorkoutCaloriesWithPhysiologicalBaseline:weightInKilograms:age:bpm:maximumHeartRate:, 0x100216824):
HR capped to maxHR by `if (param_2 <= param_3) param_3 = param_2;`.
A=max(0, (0.20*age + 0.19*weight + 0.60*clampedHR - 50)/251.04)
B=max(0, (0.07*age - 0.13*weight + 0.40*clampedHR - 15)/251.04)
Category 0 selects A, 1 B, otherwise average. Age/weight/HR semantic mapping is inferred from method signature; must validate actual calling convention and units. Constants exported at 0x108a7b1f0=0.2, 0x108a8b470=0.19, 0x108a7b048=0.6, 0x108a8b448=251.04, 0x108a7b288=0.07, 0x108a7af50=0.4, 0x108a8b478=-0.13. Confirm if output is per-minute/per-second and how it is integrated before shipping.

## Total calories path
0x1002161cc loops over HR-related samples and duration-like values, sums products. Threshold `A + (B-A)*0.3` (DAT_108a7b030=0.3). Decompiled helper 0x1002164c0 has uncertain signature; do not directly port reconstructed pseudocode without disassembly review and sample tests.

## RHR baseline fetching
0x10029f008 guards concurrent requests with isFetchingRHRBaseline, checks lastFetchedRHRBaselineDate, uses force flag and schedules async worker 0x10029fbb8. Date helper 0x1005c5384 compares calendar year/month/day. Worker calls heartRateService, callback 0x10029fc68 delegates to 0x10029f6cc. On successful nonnull result callback sets restingHeartRateBaseline and lastFetchedRHRBaselineDate, clears isFetchingRHRBaseline, invokes completion. This is fetch/update flow, NOT the baseline computation formula.

## Sleep
validateSleepDetected (0x1000a8c58) delegates to 0x1000a88ec; exact start/end/stage thresholds not established from this export.

## Engineering follow-up
1. Audit STRAP existing calories and profile field mapping; preserve existing behavior until validated.
2. Add unit tests for coefficients, category selection, HR capping, zero clamp, integration and missing-data handling.
3. Compare against paired WHOOP workout samples, then implement behind a tested change.
4. Do not treat decompiler recovered function signatures as authoritative without ARM64 argument mapping verification.
