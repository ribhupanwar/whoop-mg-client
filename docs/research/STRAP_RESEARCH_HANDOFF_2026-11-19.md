# STRAP Research Archive — New Chat Handoff (2026-11-19)

Repository: `ribhupanwar/whoop-mg-client`, production branch `main`.
Durable engineering backlog: `docs/STRAP_UI_MASTER_CHECKLIST.md`.
Previous phases: `docs/research/phase-1-12-implementation-matrix.md`, `docs/research/phase-1-12-strap-implementation-handoff-2026-11-19.md`.
Reference research repository: `ribhupanwar/dsta`.

## Preserved source research
Five original user-uploaded Phase 14 reports, archived verbatim in `docs/research/phase14/`:
- `PHASE14_HRV_BINARY_FINDINGS.md`
- `PHASE14_RHR_BINARY_FINDINGS.md`
- `PHASE14_VO2MAX_BINARY_FINDINGS.md`
- `PHASE14_RECOVERY_PIPELINE.md`
- `PHASE14_STRAP_GAP_ANALYSIS.md`

User also supplied the Antigravity Phase 14B executive report/task log, preserved as `docs/research/phase14/PHASE14B_ANTIGRAVITY_EXECUTIVE_REPORT_AND_TASK_LOG.txt`. **Important**: This is not the four complete Phase 14B markdown artifacts. Those files remain on the user's Windows computer until uploaded or pushed:
- `PHASE14B_BINARY_EVIDENCE_AUDIT.md`
- `PHASE14B_METRIC_COMPARISON.md`
- `PHASE14B_CONFIRMED_FIXES.md`
- `PHASE14B_UNRESOLVED_FINDINGS.md`

Original Antigravity location reported:
`C:\Users\ribhu\.gemini\antigravity\brain\7f9969b1-682d-4744-8dd7-565b721c43e6\`.
Phase 15 is a requested forensic verification task; do not claim its nine deliverables exist until verified.

## Existing earlier research and implementation
- `docs/WHOOP_CALORIE_BINARY_FINDINGS.md`, `docs/WHOOP_CALORIE_ENGINE_HANDOFF.md`, `docs/WHOOP_CALORIE_IMPLEMENTATION_VALIDATION.md`
- `ios/Strap/Analysis/WhoopRecoveredCalories.swift` experimental engine; not the production calculator
- `ios/Strap/Analysis/WhoopDerivedStrain.swift` and `ios/Strap/strain_raw_scale_lookup.json` experimental WHOOP-derived strain model
- `ios/StrapTests/WhoopRecoveredCaloriesTests.swift` and `ios/StrapTests/WhoopDerivedStrainTests.swift`
- Original standalone strain handoff report was discussed/uploaded in an earlier chat but has not been confirmed present as a standalone GitHub document.

## Key caution: evidence vs hypothesis
- WHOOP iOS binary fields for HRV/RHR, sleep stages, recovery levels, VO2 sources and API paths do **not** by themselves prove the proprietary cloud algorithm.
- SWS-only HRV, 'last SWS cycle', SWS-median RHR, rolling 28-day baseline, VO2 30-day smoothing, respiratory-rate recovery penalty and exact formula weights remain unverified without caller-chain/backend/paired-device evidence.
- Phase 14B reports simulated comparisons: SWS 37.72ms vs quiet 29.70ms; nap-blended 30.76ms; these are **not measured WHOOP parity results**.
- Confirmed STRAP code issue: `CaptureAnalysis.swift` previously weighted multiple sleep sessions into nightly HRV, potentially mixing naps. Commit `897cfb307fe6b597074fb58f6377c9c9795822cd` on main switched nightly HRV to primary sleep only, preserving missing-data behavior. Tests and iOS CI were queued immediately after commit; re-check results, add explicit nap regression test.
- STRAP RHR already used the longest primary sleep; do not misreport it as all-session blending.
- Sleep onset earlier differed about 16 minutes and wake end about 9 minutes from WHOOP in user comparisons; investigate raw CSV and sleep detector, never apply hard-coded time offsets.
- No replacement of production Recovery, Calories, Strain, HRV or VO2 algorithm without tests and paired real-world validation.

## Working requirements
- Accurate BLE packet decoding and reconnect, automatic activity detection, sleep staging, manual edit recalculation, HRV/RHR/recovery/strain/calorie/VO2 fidelity.
- WHOOP-like home ring geometry (104pt diameter, 8pt stroke, 18pt ring spacing), center value and percent typography, smaller accurate battery icon; pixel-match all tiles/tabs/charts.
- Preserve purchased Proxima Nova and DIN Pro fonts. Never delete historical data or fabricate health readings.
- Verify GitHub Actions before claiming a successful IPA; report exact commit SHA, test result and pending work.
- Existing autonomous STRAP engineering automation reads `docs/STRAP_UI_MASTER_CHECKLIST.md`; do not assume automation work is complete until GitHub verification.

## New chat restart instruction
'Continue STRAP in ribhupanwar/whoop-mg-client. First read docs/research/STRAP_RESEARCH_HANDOFF_2026-11-19.md, docs/research/phase14/, docs/STRAP_UI_MASTER_CHECKLIST.md and current main/CI. Audit evidence before changing production formulas; implement verified fixes with regression tests and push to main. Request the four missing original Phase 14B markdown files from Antigravity if not yet archived.'
