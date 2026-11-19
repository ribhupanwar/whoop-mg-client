# Phase 13 — Verified activity-detection engineering record (2026-11-19)

This is a **reconstructed source-linked engineering handoff**, not a verbatim recovered original Phase 13 research report. Preserve that distinction.

## Changes confirmed in main history
- `66fad2241e010eaafa16d9b1e6b5680ddf09df97`: opt-in ten-minute auto-activity comparison; original default detection unchanged.
- `71495ed6108efec8b27f9f051c3e0d45270d94f5`: clamp step-driven activity end to last measured motion instead of HR cooldown.
- `b06c2c2c4e2d67837ccaa8fbf885e0fd0b3688af`: document recent step evidence separately from unverified gait byte.
- `e3982ec20b70924ca422fd94e0a4f995788714d6`: wrap-aware step-counter deltas.
- Earlier related commits: `de738dcca85c110a15d774ac7619f24a9c6738ac` (cooldown handling), `6d3d9e7531e3c32ad6d0ce19af4d6348194a91fc` (stale gait), `9cd2fee8d714f197854161ea8b9507c1c7d1a08f` (step counter).
- `17cc72574f299f8c9d6ab2af2843ed0a17fbf136` was reported as a Phase 13 regression-test commit; confirm exact content in git history before attributing test coverage.

## Current implementation entry points
- `ios/Strap/Analysis/Activities.swift`
- `docs/research/phase-1-12-strap-implementation-handoff-2026-11-19.md`
- `docs/STRAP_UI_MASTER_CHECKLIST.md`

## Engineering requirements and verification gaps
- Running/walking must require real measured step-counter evidence and/or validated HR conditions, not an unverified gait flag alone.
- End timestamps must reflect measured motion, not inflated HR cooldown; test HR-only activities separately.
- Test counter wrap/reset, duplicated timestamps, motion gaps, false sedentary walks, off-wrist periods, overlapping manual/GPS sessions and persistence.
- WHOOP's public 2026 minimum auto-detection duration of 10 minutes is not proof of its internal classifier; opt-in experiments should not silently change production defaults.
- Physical band testing and comparison to WHOOP reference sessions are pending; do not claim pixel parity or activity parity from unit tests alone.

## Scope warning
The original full Phase 13 investigation document was not available in the repository audit. This file preserves confirmed GitHub code-history evidence and known research questions without fabricating original binary findings.
