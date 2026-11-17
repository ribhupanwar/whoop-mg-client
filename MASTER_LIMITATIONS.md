# STRAP remaining limits and device validation

This accompanies the complete 126-item `MASTER_PROGRESS.md`. Implementation, deterministic tests, physical validation and scientific validity are separate. No item becomes complete from compilation alone. The user's returned last-night Sleep is preserved; no uninstall, live database replacement or defaults reset was performed.

## External inputs and scientific limits

| Items | Remaining limit | Required evidence/input |
|---|---|---|
| B3 | Type 52 (0x34) is identified as historical IMU, but its payload framing is not established. It remains raw; the 0x2F layout is not blindly reused. | Real firmware-specific packet captures or verified framing specification. |
| D14 | Repeated HealthKit UUIDs are idempotent and existing originals win. Different UUIDs/providers with matching times are not automatically collapsed; they can be separate genuine events. Imported sources never add duplicate daily totals to band measurements. | Shared source identity or explicit reconciliation decisions for mirrored third-party records. |
| H10 | No in-app Strava account/upload flow is enabled. Local FIT/GPX export works without it; cloud processing/duplicate acceptance has not been tested. | STRAP-owned client registration/redirects, protected token exchange deployment, athlete `activity:write` grant. No borrowed tokens or embedded secret. |
| G2 | Validated biological age cannot be derived from the available wrist inputs or Aura's closed app source. Fitness-age comparison is a disclosed estimate, not biological age. | A validated method and the actual required biomarkers/source; never substitute a fabricated age. |
| C5–C8, C14 | Respiration is an RR-derived RSA estimate; optical oxygen and temperature lack clinical calibration. VO2/energy/fitness-age methods are estimates. Official WHOOP imports are labelled source values. | Paired qualified reference measurements, calibration and sufficient longitudinal user history. |
| A11, A14, E4 | WHOOP CSV exports supply stage totals, not timestamped stage epochs. Imported stage totals do not create an invented hypnogram. Local staged timelines remain algorithm estimates. | Epoch-level original source data for official imported timelines, and paired sleep ground truth for local accuracy. |

## Device checks still required

- A1, A4–A10, A12–A14: actual returned Sleep boundaries, manual correction replay across an upgrade, nap/rest rejection, awakenings and staging accuracy. User confirmation that Sleep returned is not a stage-accuracy claim.
- B2, B4–B12: real 5/MG live RR completeness/timing, firmware quality bits, actual V20/V21/V22/V26 payloads, nominal IMU rate versus measured sampling, off-wrist/charging transitions, reconnect/background/long-drain behavior. Current `wearing` is an HR-presence proxy, not a newly validated wear bit.
- D1–D12: real activity boundaries, route accuracy, cadence/pace, background location, pause/resume and battery impact. GPX retains original coordinates/times; FIT uses standard timestamp/coordinate quantization. Missing HR/altitude/calories are omitted. No TCX is emitted when its required data would have to be invented.
- H2–H5: notification permission/delivery and physical wrist actuation. The band's verified command holds only the next occurrence; reconnect after waking is required to send the subsequent weekly occurrence. A BLE acknowledgement or queued phone request does not prove a wrist buzz.
- H7–H8: HealthKit read access and measured workout export on the user's signing profile. A free signing account may not grant HealthKit; an empty read result can also mean no accessible samples.
- I1, I11, I13: install-over continuity with the user's existing signer/profile, app container and retained manual edits. Do not uninstall to test an update. CI IPA is ad-hoc validation packaging and must be re-signed by the existing sideloading setup.
- I6–I8: actual OS-delivered MetricKit crash/hang/performance payloads and measured physical battery/memory intervals. Empty OS archive does not prove crash-free operation. Synthetic archive tests do not constitute a real crash investigation or Instruments profile.
- F1, F4–F15: same-scale reference screenshots, touch/VoiceOver/scrolling and physical contrast/layout review. Latest-main visual changes are retained; pixel equivalence is not established by font packaging or UI test success.

## Deliberate source-preservation policies

- Measured band/local values and edited sleep bounds take precedence over imported display fallbacks. Official source rows remain intact and can be inspected/exported.
- Manual merge is explicit, same date/type and reversible. Self-reported minutes are summed with overlap explicitly unknown; it never invents continuous measured activity, HR, strain or calories. Measured/cross-provider sessions remain separate.
- CSV/JSON reports are filtered reports, not restore packages. Local records use their recorded day; activities/HealthKit/GPS use start, saved sleep uses wake, raw seconds/RR use stored timestamps. Shared source-date resolution now aligns import, charts, journal and report filtering to original wake-date/cycle linkage; workouts retain their original start day. New overnight/incremental regression tests await native validation. Undated rows are counted/excluded by filtered export rather than assigned fabricated dates.
- Report exports include loaded canonical derived records and committed raw SQLite history. Unsupported raw packets, older recovery revisions, OS reports and full persistence evidence remain in full diagnostics/backup. An in-flight unsaved record can appear after persistence.
- Restore merges missing raw seconds/UUIDs and missing storage keys; existing keys/manual edits win. Conflicting incoming collections remain archived, rather than silently overwriting an existing collection. Restore remains a physical-device validation item.
- Raw live RR retention has no artificial display-window retention cap; actual durable storage is finite. UI/analysis windows stay bounded. An OS kill before an in-flight write can lose that uncommitted interval; successful persistence and pre-ACK history capture are separately tracked.

## Approval boundary

PR #45's ZIP/chart merge was explicitly approved and completed. PR #44 is closed unmerged. Calorie research PR #47 was explicitly approved and merged as `2fc4ae0`. Broader master changes remain in draft PR #46 without merge approval. Integrating existing main into the draft does not modify main. No private WHOOP ZIP, health values or journal notes were published as repository/CI fixtures.

## Calorie research validation

The isolated recovered WHOOP 5.78.0 calculator and 13 deterministic tests are included for research only. It is not called by production or used to recompute historical records. Covered-window integration includes resting energy; a mathematical net-above-resting difference is not verified WHOOP active calories. Real matched validation remains blocked by missing profile/configured anchors/full HR samples and explicit comparable energy fields. Raw baseline enum mapping, final-interval count predicate and upstream reference-rate/HR preprocessing still need binary/call-site evidence. See `docs/WHOOP_CALORIE_IMPLEMENTATION_VALIDATION.md`.
