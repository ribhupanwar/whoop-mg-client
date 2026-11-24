# STRAP research adoption: RR artifacts, beat timing, and wrist-angle sleep evidence

Status: **experimental / non-production**. Do not replace production HRV or sleep boundaries until fixture-backed results pass. Keep original sensor archives, pairing, signing, fonts, and manual sleep edits untouched.

## 1. RR artifact correction (Lipponen–Tarvainen family)
- Input: ordered *individual* RR beat events with verified timestamp and source, not a per-second packet timestamp repeated for every RR beat.
- Preserve raw RR; separately label missing/extra beats, ectopic short-long pairs, isolated outliers and non-physiological values. Correct only when enough neighboring clean beats support the classification.
- Output: raw beats, corrected NN series, correction count and fraction, excluded beats, valid coverage, gap boundaries, RMSSD before/after. Never interpolate across missing history, off-wrist, disconnects or unverified packet timing.
- Comparison: existing rolling-median NN filtering vs experimental artifact correction on identical captures. Report absolute error versus reference, false corrections, retained coverage and RMSSD stability. No claim of exact WHOOP algorithm.
- Acceptance: deterministic synthetic fixtures (isolated spike, ectopic pair, missed beat, extra beat, prolonged corruption, reconnect duplicate, zero padding, packet gap); no worse performance on available anonymized captures; no silently fabricated HRV.

## 2. Beat-level timestamps
- Provenance: identify whether each BLE format provides absolute beat time, relative delta, sample-second bucket or merely a list of RR values. Document evidence per firmware layout before inferring timing.
- For formats with trustworthy RR durations and a verified anchor, reconstruct within-packet beat boundaries backwards from the anchor; mark derived timing and uncertainty. Never pretend second-resolution archive timestamps are measured beat timestamps.
- Stable event key: device/session + anchor + within-packet index + source/sequence, with collision-safe replay handling. Preserve both raw and derived timestamps and original packet bytes/reference.
- Verify sum of RR durations against packet interval and clock drift; mark ambiguous anchors as unknown rather than assigning precision. Do not bridge clock loss or reset.

## 3. van Hees-style wrist z-angle / actigraphy evidence
- Requires raw calibrated 3-axis acceleration with coordinate orientation and actual sampling rate. Dynamic-acceleration magnitude alone is insufficient to reconstruct z-angle.
- Compute wrist orientation from gravity/low-pass vector, then z-angle and sustained change metrics in time windows, with explicit wrist-off, missing-sample and rotation handling.
- Compare inactivity-based sleep-window candidates with existing HR + band-state algorithm. Use as *additional evidence*, not an automatic replacement for sleep stage classification or a hard sleep-end override.
- Replay scenarios: awake in bed, delayed onset, 2–5 minute bathroom break, returned to bed without proven sleep, actual resumed sleep, final wake, wrist-off, and missing packets.
- Never tune thresholds to one user's 6:26–6:38 AM example; assess onset and wake error across nights.

## Merge gates
1. Document exact raw field mapping and source/license provenance for each firmware.
2. Add independent, deterministic tests for both successful and failure paths.
3. Run before/after metrics on anonymized raw captures; publish coverage, errors and tradeoffs.
4. Confirm no regression in production HRV/RHR/recovery/strain, sleep edits, and BLE persistence.
5. Exact-head iOS + protocol CI green; review and only then enable via an explicit opt-in feature flag.
6. No copying AGPL code into STRAP without license review. Prefer independently written implementations of published methods.

## Initial audit findings
- `Hrv.swift` currently applies rolling-median NN acceptance and splits missing-second runs; PR #193 added valid-RR-first retransmission choice.
- `SleepDetect.swift` has a 300-second sustained-up trimming rule; band state 3 can remain set after a short bathroom interruption.
- `BandLink.swift` persists capture and database chunks before sending historical ACK; do not duplicate this.
- `BandLink.swift` labels experimental SpO2 candidates as uncalibrated.
