# Consolidated Woop-reference accuracy follow-up

Depends on #292, #291 and #288; complementary #289/#290. No private sensor rows committed.

## Reproduced boundary mechanism
A private real-night targeted Python replay of the Swift HR-transition splitter and terminal-up trimming across 6h, 12h, 24h, 48h, 96h and 240h active-HR reference scopes showed an independently observed later band-sleep interval was shortened below the existing 60-minute minimum by internal elevated-HR splits. A bounded internal corroboration guard preserves the resumed interval; the tested modeled terminal-trim duration before leading-up refinement increased from 38–45 minutes to 99–100 minutes. Leading up trimming remains required to distinguish the approximately 70-minute resumed interval from the preceding interruption. This is not a complete native Swift replay, not proof of exact final wake, and not a clinical validation. Do not claim a production fix until native CI and private real-night replay.

## Adoption
- Require established nocturnal sleep, >=48 unique quiet sleep-hint seconds per minute and modest HR elevation to protect internal HR transitions. Retain leading onset, terminal wake, wearing, movement and normal minimum-duration guards. Do not disable wake veto or simply increase global merging to 90 minutes.
- Personal overnight HR median and habitual midpoint are shadow diagnostics only, using at least 14 distinct, prior, complete, corroborated same-timezone nights with adequate measured minute HR. Floor 40 BPM is a reference observation; no production threshold changes.
- Existing #290 provides individual RR bucket quality evidence. Do not collapse repeated RR pairs or loosen duration gates without beat identity validation. No HRV scaling.
- HR-only fallback, 90-minute grouping, respiration vendor-source mapping, historical temperature backfill and calibrated SpO2 remain research: static symbols do not establish hardware field semantics or clinical validity. Existing sensor/respiration PRs must be assessed before any new production change.
- Tests use synthetic data; private captures stay local. Run exact-head native iOS checks and actual private detector replay before release.
