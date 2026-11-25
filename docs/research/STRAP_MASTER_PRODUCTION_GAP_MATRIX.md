# STRAP Master Production Gap Matrix

**Main commit at audit start:** `c6d2916` (2026-11-25)
**Auditor:** Kilo (automated engineering)
**Method:** Live GitHub/GitHub-Actions forensics + direct source inspection on `main`. No status taken from prior audits without re-checking current code.

> Status legend: VERIFIED · IMPLEMENTED — HARDWARE VALIDATION PENDING · EXPERIMENTAL · BLOCKED BY MISSING DATA · PROPRIETARY / NOT REPRODUCIBLE · FAILED

## P0 — Data loss / build / crashes

| ID | Sev | File:Line | Current behavior | Expected | Root cause + evidence | Existing PR | Proposed fix | Regression test | CI evidence | Disposition |
|----|-----|-----------|------------------|----------|-----------------------|-------------|--------------|-----------------|-------------|-------------|
| P0-1 | P0 | `ios/Strap/Analysis/Hrv.swift:927` (at `c6d2916`) | main HEAD fails to compile: `cannot find 'previousTs' in scope` | main compiles | `c6d2916` removed `previousTs` decl + 4/5 uses, missed the out-of-range branch. CI run on `c6d2916` ios = failure. | **#237 (this fix)** | Remove stray `previousTs = nil` | existing HRV tests compile+pass | PR #237 exact-head ios pending | **FAILED → fix in #237** |
| P0-2 | P0 | `ios/Strap/Band/BandLink.swift:1001` | Incomplete history could be suppressed by foreground cooldown on a pre-#221 build | Resume drains missing records | Real BLE log: 29× `analysis deferred` through 2026-11-25T01:06:11Z, all **before** #221 merge 10:18 IST → pre-fix build. | merged #221; test locked in #232 | `shouldResumeIncompleteForeground` | `testIncompleteNightResumesDespiteForegroundCooldown` | #232 green, merged `09441fb` | **VERIFIED** |
| P0-3 | P0 | `SleepSession.retainingUncovered` `:199-236` | Stale auto `isEdited` wake could freeze early boundary | Late confirmed sleep tail extends; manual edits preserved | Merged #220/#223; quiet-tail + authoritative provenance | merged | — | `SleepSessionTests` late-tail cases | main green | **VERIFIED** |

## P1 — Physiological accuracy

| ID | Sev | File:Line | Finding | Disposition |
|----|-----|-----------|---------|-------------|
| P1-1 | P1 | `Recovery.swift:93`, `StressWindows.swift:26` | Stress `0.0` Home bug: path already returns `nil`+reason when RR/baseline missing; the visible defect was a misleading baseline-day label | **VERIFIED** fixed by #227/#230 |
| P1-2 | P1 | `Hrv.swift` extendedDiagnostics | ACF1 jitter gate + RR coverage diagnostics are observation-only (no estimator change) | **IMPLEMENTED — HARDWARE VALIDATION PENDING** (#235 merged) |
| P1-3 | P1 | SpO₂ summary | Off-wrist candidates excluded; replay-invariant unique-second | **VERIFIED** #228/#231, #233 open |
| P1-4 | P1 | RR 0x2A37 vs Type-40 | Counter consistency / standard-RR retention | **BLOCKED BY MISSING DATA** — open #218/#219, needs multi-night RR captures |

## P2 — Performance / UI / secondary

| ID | Finding | Disposition |
|----|---------|-------------|
| P2-1 | Skin temperature baseline night interpolation label | VERIFIED #229 |
| P2-2 | Healthspan coverage boundaries, RR replay priority tests | open #224 (draft) |
| P2-3 | Configurable local backup cadence | open #236 (draft) |

## Open PR ownership (conflict avoidance)

- #218/#219 → `BandLink.swift` (RR). #233 → `Recovery.swift`. #235 → `Hrv.swift`/`metrics.py` (merged). #236 → `DailyLocalBackup.swift`. #224 → tests only.
- This audit's changes are confined to the build-break one-liner (#237) to avoid overlap.

## Notes
- No TODO/FIXME debt in `ios/Strap` (grep clean).
- Python protocol suite: 427 passed, 1 skipped on `main`.
- Private sensor captures used read-only; never committed.