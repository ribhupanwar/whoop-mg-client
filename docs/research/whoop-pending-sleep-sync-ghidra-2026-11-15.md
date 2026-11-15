# WHOOP pending sleep synchronization — Ghidra observations (2026-11-15)

Status: **behavioral research; no production sleep-detection algorithm recovered**. Based on decompiled excerpts supplied by the device owner. Addresses refer to the inspected WHOOP ARM64 image and are not stable APIs.

## Observed call chain

- `WHPApp::startSyncPendingSleep:` at `0x10004beb0` dispatches a block to the main queue when not already on the main thread. The block implementation is `FUN_10004bf28`.
- `FUN_10004bf28` creates an `NSTimer`-related block with a double constant `1.0` and a repeat flag `1`. The block implementation is `0x10004c020`. The exact Objective-C selector behind the timer thunk should be confirmed before treating the interval as guaranteed.
- `0x10004c020` increments a by-reference counter, dispatches a background block at `0x10004c104` to the global queue, and executes cleanup-related calls if a shared flag is set or the counter exceeds `0x1d` (29). The code is consistent with roughly 30 ticks of polling, but exact timer invalidation behavior requires selector resolution.
- `0x10004c104` calls `WHPAppData.loadCachedCycleEntityForCycleDate:` via an Objective-C message-send thunk. If a cycle entity exists, it obtains a related object's `state` and compares it to the string `pending`; the inverted comparison is stored in a shared byte. The precise object relationship and behavior on nil/missing state remain unverified.
- `WHPApp::sleepAutoDetectStartedAt` at `0x10004e0b4` returns the object at `self + 0x170`; this is a getter, not proof of how that timestamp is set.
- `HomeViewController.validateSleepDetected` at `0x1000a8c58` retains its object, calls `FUN_1000a88ec`, then releases it. The decompilation of the callee is not reliable enough to infer sleep classification or edit semantics.

## Independent STRAP implementation implications

1. Keep **candidate detection**, **pending synchronization**, **finalized sleep**, and **manual correction** as distinct states. Do not replace physiological evidence gates with a timer or duration-only rule.
2. If implementing polling, use bounded attempts, explicit cancellation, and no overlapping in-flight fetches; a timer tick dispatching asynchronous work does not imply the previous fetch finished.
3. Never treat a missing cached entity or unknown state as proof of finalization. Only a verified terminal state can finalize an independently computed sleep session.
4. A manually corrected bedtime/wake time must remain canonical through archive refreshes and background sync; only an explicit user edit may change its bounds.
5. On a verified sleep change, invalidate derived staging/efficiency/recovery and recompute only with sufficient raw data. Unknown measurements remain unknown.
6. Add deterministic tests for pending-to-finalized transitions, missing cache, 30-tick timeout, overlapping async requests, cancellation, manual edit preservation, and missing RR/HR.

## Not established by this evidence

WHOOP's sensor-based onset/offset detection, wake/REM/deep staging, sleep performance formula, recovery formula, whether pending sleep is remote or local, or the root cause of STRAP's reported end-time drift. Do not claim WHOOP parity or change production scoring solely on these observations.
