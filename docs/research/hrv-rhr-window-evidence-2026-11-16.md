# WHOOP HRV/RHR window evidence — 2026-11-16

## Evidence and limitations
- WHOOP support: HRV uses RMSSD and is measured during the deepest period of sleep on 4.0/5.0/MG: https://support.whoop.com/s/article/Heart-Rate-Variability-HRV-Insights-WHOOP-Metrics
- WHOOP research FAQ (WHOOP Unite): HRV measured in a 5-minute sleep period, usually last five-minute episode of last slow-wave sleep; raw RR per second may contain zero beats when noisy or no beat occurred. https://sensorlab.arizona.edu/sites/default/files/2023-05/WHOOP%20Unite%20Research%20FAQs_0.pdf
- WHOOP Recovery support describes weighted nightly HRV emphasizing SWS and later-night periods: https://support.whoop.com/s/article/WHOOP-Recovery
- A 2026 published WHOOP methods description similarly describes excluding wake/low-quality epochs and weighting by SWS probability and recency: https://www.nature.com/articles/s41514-026-00552-w_reference.pdf

These sources differ in the exact summary window (single last SWS five-minute epoch vs weighted epochs). They do not establish a complete reproducible 5.0/MG production formula. Do not hardcode an assumed 1.5x weighting or claim ±2 ms accuracy.

## Current STRAP behavior to compare
- `ios/Strap/Analysis/Hrv.swift`: gap-aware RMSSD and RR filtering.
- `ios/Strap/Analysis/CaptureAnalysis.swift`: computes per-session resting HRV, then weighted average across sleep sessions by validated quiet-window seconds. RHR uses longest sleep session and five-minute resting window.
- Existing 2026-11-16 commit 17e02b0 guards against unconfirmed leading RR artefacts; follow-up 0880608 adds regression test. CI status must be checked before calling it verified.

## Next bounded engineering experiment
1. Build per-epoch 300-second HRV diagnostics (epoch start/end, sample coverage, accepted/rejected RR, RMSSD, mean HR, motion, stage evidence).
2. Compare **existing** nightly weighted estimator with (a) last qualified deep-sleep 5-minute epoch and (b) weighted late-night/SWS epochs, without changing production outputs.
3. Reject awake and low-signal epochs; never bridge missing or rejected RR intervals.
4. Compare to WHOOP reference values for multiple paired nights, report MAE and coverage before choosing an estimator. Keep an independent RHR comparison (lowest sustained vs stable 5-minute median) and don't conflate with HRV.
5. Preserve manual sleep boundaries and recompute derived metrics on edit; test midnight/late sleep cycle strain separately.

## Calibration notes
- Kubios can serve as independent RR analysis, not proof of identical WHOOP output.
- Avoid directly deleting beats then taking differences between previously nonadjacent beats.
- Distinguish WHOOP official descriptions, research papers, and unverified reverse-engineering hypotheses.
