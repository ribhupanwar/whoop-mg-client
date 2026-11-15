# Sleep and recovery investigation notes (2026-11-15)

Status: **research notes only**. These observations are from filenames and user-inspected localization resources of an independently obtained WHOOP iOS app. No proprietary executable, resource tables, fonts, or copied implementation are committed here.

## Evidence and limits

- A sleep-details localization resource labels the editable fields **Bedtime** and **Wake up Time**, under **Edit Time In Bed**. This suggests that time-in-bed boundaries and inferred sleep stages should be modeled separately; it does **not** disclose WHOOP's sleep-stage algorithm.
- The same resource describes recovery as calculated using a **single sleep activity**, and converting a nap to sleep as a way to recalculate recovery. This is evidence of the user-facing behavior, not proof of the internal data model.
- Deleting a sleep activity is described as deleting its scores while retaining heart-rate data. Raw sensor data should therefore be stored separately from derived sleep and recovery records.
- Health Monitor fallback text describes HRV, resting HR, respiratory rate, blood oxygen and skin temperature as sleep-associated measurements, and notes that a missing sleep/recovery can prevent presentation. This does **not** establish formulas, on-device/server execution, or exact recomputation triggers.
- The app package contains a recovery-to-recommended-strain table and a nonlinear raw-to-displayed-strain lookup. Their presence alone does **not** identify how raw strain is accumulated or which metrics use these tables.

## STRAP implementation checklist (not yet implemented)

1. Persist raw HR/RR/IMU samples independently of sleep activity records.
2. Distinguish the user-editable time-in-bed window, inferred sleep intervals, sleep-stage segments, and naps.
3. Select one explicit primary sleep session for nightly recovery; guard against duplicates and ambiguous primary selection.
4. On edit or conversion, invalidate sleep-dependent derived values and recompute **only where underlying samples and validated algorithms are available**. Show unavailable rather than inventing values.
5. Protect manually edited/finalized time bounds from automatic background overwrites, while allowing explicit correction.
6. On delete, remove the derived sleep record and associated scores without erasing underlying sensor history.
7. Add tests for edit→recompute, duplicate sleep, nap→sleep, missing RR, preserved HR on delete, and no silent endpoint drift.

## Open questions

- Where is the sleep staging implementation and how does it reject motion/awake periods?
- How are nightly RR samples quality-filtered and aggregated for HRV/RHR?
- What is the actual recovery scoring model and when is it refreshed?
- How is raw strain accumulated before display scaling?
- Is the relevant computation local, remote, or hybrid?

Do not treat this document as validation of WHOOP-equivalent accuracy. Any implementation requires independent testing against consenting user's data.
