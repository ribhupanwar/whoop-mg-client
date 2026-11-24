# STRAP SpO2 cross-repository gap audit (2026-11-23)

## Sources
- OpenWHOOP: https://github.com/hunterchen7/openwhoop/blob/main/docs/spo2-research.md
- OpenWHOOP official-app replication analysis: https://github.com/hunterchen7/openwhoop/blob/main/docs/whoop-sensor-replication.md
- OpenStrap protocol: https://github.com/OpenStrap/protocol
- NOOP independent v18 tail study: https://github.com/ryanbr/noop/issues/103

## Verified STRAP gap and patch
- `ios/Strap/Protocol/V18Record.swift` explicitly calls inner[74] a *candidate* (not calibrated SpO2).
- `ios/Strap/Analysis/Recovery.swift` returns a research-only candidate summary.
- `ios/Strap/HealthView.swift` previously rendered that candidate as a percent in the diagnostic tile, despite labeling it unvalidated. This branch replaces the candidate percent with an unavailable measurement placeholder and preserves the count for diagnostics.
- The separate Health Monitor oxygen tile consumes `monitor[.oxygen]`; its provenance must be traced before changing it. Do not assume it uses the v18 candidate.

## OpenWHOOP comparison and evidence limits
- OpenWHOOP's JADX-derived study identifies historical k=21 optical packets (three green and three IR arrays, historical packet 0x2f), with candidate offsets green @20/220/420, IR @632/832/1032, green count @16, IR count @622, total 1244 bytes. These are **source-reported**, not yet verified on a STRAP WHOOP 5/MG capture.
- OpenWHOOP reports the official client uploads optical data and SpO2 is computed cloud-side, not by an available local proprietary algorithm.
- Their overnight passive capture produced no optical k20 packets; k21 emission depends on unresolved firmware/on-wrist/sleep conditions. No safe SpO2 trigger command has been established.
- Their experimental R=(AC_red/DC_red)/(AC_ir/DC_ir) method still needs a verified red-channel mapping and calibration. No absolute SpO2 % should be generated from the v18 candidate or raw ADC counts.
- OpenStrap's R24 red/IR fields are raw relative ADC counts, not calibrated percentages. NOOP's v18 optical tail likewise has no paired SpO2 reference.

## Next bounded implementation work
1. Audit existing historical packet framing and archival to see whether k=21 records are preserved even when undecoded; add fixture-backed, non-destructive k21 extraction only after confirming actual packet offsets/length.
2. Count k20/k21 and unknown optical packets in sync diagnostics; never drop historical bytes before durable archival.
3. Use real anonymized overnight STRAP captures and official-app/pulse-ox reference before labeling red/IR or calibrating percentages.
4. Add tests for truncated/malformed optical packets, missing channels, wrist-off, missing capture, and no fabricated SpO2 number.
5. Do not send speculative firmware/config writes or copy third-party code without license review.

**Status:** UI guard committed on this branch; decoder and calibration parity **not established**. This is a research plan, not a claim that WHOOP SpO2 has been reproduced.
