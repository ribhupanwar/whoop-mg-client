# Isolated recovered calorie calculator

Code: `ios/Strap/Analysis/WhoopRecoveredCalories.swift`  
Tests: `ios/StrapTests/WhoopRecoveredCaloriesTests.swift`  
Basis: `WHOOP_CALORIE_ENGINE_HANDOFF.md` and `WHOOP_CALORIE_BINARY_FINDINGS.md` (WHOOP 5.78.0 ARM64 excerpts).

## Implementation boundary

This is an isolated research API, with **no production call sites**. `Calories.swift`, its consumers, history persistence and licensed fonts are unchanged. No cache is invalidated and no historical estimate is recomputed or replaced.

Implemented recovered arithmetic:

- Resting revised Harris–Benedict rates in kcal/s with height explicitly in meters; raw 0/1 and raw-2 mean of separately clamped rates.
- Workout HR rate with the recovered coefficients/divisor, maximum-HR cap and per-formula zero clamp. Its standalone raw-baseline helper averages every value other than 0/1, as documented; this does not infer the unresolved resting enum metadata.
- The 30% HR-reserve threshold and two-register slope/intercept interpolation, not the misleading scalar decompilation.
- Rate times covered duration, with every observed adjacent timestamp interval capped at 3 seconds.

Explicit application/research policies, **not claims of recovered binary edge-case parity**:

- Known resting baseline codes have numeric names; there is no automatic `Sex` mapping or missing-profile default.
- Profile guards require finite positive weight/height and finite nonnegative age. They are arithmetic guards, not recovered WHOOP clinical acceptance bounds. Nonfinite/overflowed arithmetic fails closed.
- The reference rate at the maximum-HR anchor is supplied explicitly. A caller may experiment with the workout helper at maxHR; the provided excerpts do not establish every upstream anchor-construction call site.
- The workout helper caps HR. The integration interpolation does not silently add another cap to its input; its shown ARM64 multiplies the supplied HR. Upstream HR preprocessing remains unverified.
- Tail policy is required. `observedIntervalsOnly` leaves the final sample without invented duration. `repeatFinalInterval` explicitly models the recovered append-last experiment, but the binary count predicate is unresolved. Empty/singleton/duplicate/missing endpoints never receive a fabricated one-second duration.
- Timestamp order is never silently changed. Out-of-order finite timestamps reject the experiment to prevent overlapping/double-billed intervals. Missing/nonfinite timestamps and missing/nonpositive/nonfinite HR break adjacent coverage instead of bridging it. Exact binary behavior for these cases remains unverified.
- No covered intervals is a missing-result error, not a made-up zero-calorie workout. A computed negative interpolated rate is rejected rather than adding an unsupported clamp.

## Output semantics

`integratedKcal` includes the resting rate during covered low-HR intervals. It is **not active-only** and is **not a whole-day total**. Missing time and long gaps are not backfilled. `restingKcalForCoveredSeconds` uses precisely the same covered duration. Their signed difference, `netAboveRestingKcal`, is a mathematical comparator, **not a verified WHOOP active-energy field**.

An independent decimal fixture (synthetic profile 70 kg, 1.75 m, age 30; raw baseline 0) gives resting 1695.667 kcal/day or 0.019625775462962963 kcal/s. Two covered resting seconds integrate 0.039251550925925926 kcal, while the above-resting difference is zero. This proves the calculator's total-like semantics mathematically; it does not prove which WHOOP UI/API call site exposes that value.

For an explicit 0.2 kcal/s reference at maxHR 187 and restingHR 55, threshold is 94.6. HR [60,150,187] at times [0,1,3] integrates 0.275170227673561 kcal over 3 observed seconds. Explicit final-interval repetition adds 2 seconds and 0.4 kcal. These values were calculated independently with Python `decimal`, not by copying the Swift implementation into its tests.

## Real uploaded WHOOP export audit

The user-supplied original ZIP was inspected locally, without publishing its health values, dates or journal notes:

- 18 physiological cycle rows and 11 workout rows.
- All 11 workouts match an original cycle by cycle-start/timezone; all 11 matched pairs contain numeric exported energy, and workout energy does not exceed the corresponding cycle energy.
- Neither CSV provides separate active-energy and total-energy fields.
- The export has no weight/height/age/baseline profile or full timestamped HR stream. Workout mean/max HR do not reconstruct the observed HR trajectory or 3-second coverage.

This is consistent with different workout/cycle observation windows, but **cannot distinguish active versus total energy**. It does not establish the correct raw baseline enum, configured HR anchors, binary tail branch or model percentage error. No default profile, constant mean-HR trajectory, fabricated measurement or invented error percentage is substituted. User authorization to assume research scenarios does not turn synthetic inputs into real WHOOP validation.

Official public WHOOP data documentation inspected on 17 November 2026:

- https://developer.whoop.com/docs/developing/user-data/workout/
- https://developer.whoop.com/docs/developing/user-data/cycle/

Both expose `score.kilojoule` in examples; those pages do not define separate active/total fields or resolve the calorie semantics. Unit conversion is kcal = kJ / 4.184; it is not a justification for comparing different energy definitions or time windows.

## Validation gates

- Deterministic XCTest coverage: independent resting/workout numeric anchors, raw-baseline mean/clamps, capped workout HR, threshold equality and slope/intercept, above/below threshold, weighted sums, explicit tail policies, three-second cap, empty/singleton/duplicates, missing HR/time, invalid order/counts, nonfinite inputs/overflow and unchanged production arithmetic.
- Native GitHub Actions: pending; do not label the module tested until the actual simulator run succeeds.
- Real matched workout/cycle comparison: BLOCKED by missing full HR/profile/anchor and explicit active-versus-total reference evidence. Percentage error is not reported without comparable inputs.
- Production integration: disabled. It requires passed native tests, resolved call-site/enum/tail semantics and matched real data comparisons first.
