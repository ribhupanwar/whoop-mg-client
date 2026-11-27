# Sleep continuation reference audit (2026-11-27)

Reference: user-supplied Woop unsigned IPA, build identifier 4a3ef0e. Static ARM64 symbols and constant objects confirm separate night-continuation, morning-reonset and night-tail grouping concepts. Relevant constant values: nightContinuationGapMin=90, nightTailBridgeMaxMin=90, morningStillnessWindowMin=180, morningReonsetBandAsleepFrac=0.60, morningReonsetRestingHRMult=0.90. These are observations of one reference build, not WHOOP's algorithm, not evidence of execution conditions, and not a license to copy implementation.

## Adoption decisions
- STRAP already separates SleepDetect, SleepSession, SleepStager, and canonical nightly metrics. PR #288 adds an independently gated 30–45 minute continuation path; keep ordinary 30-minute merge policy and require real detector replay before extending it further. Do not duplicate the active branch or transplant reference thresholds.
- Adopt bounded post-wake diagnostic context (up to 180 minutes) as an observation horizon only, never as an automatic sleep extension. Export preserves canonical bounds, leaves stage labels outside the saved window blank, retains gaps, and reads the durable archive. Existing CSV columns and default window-only behavior remain compatible.
- Do not transplant the 0.90 HR multiplier: a reference baseline's meaning and control flow remain unverified. A resumed sleep interval may have higher median HR than the preceding interval.
- Retain original staging, respiration, RR-quality checks and manual corrections. Stage priors/transition probabilities and 16-hour spans require independent validation, not just static symbols.
- Next validation: compare full production detector output before/after #288 using a private retained capture, including onset, resumed candidate acceptance, terminal wake, canonical persistence and nightly biometrics. Use synthetic/anonymized fixtures in public CI. No private sample records committed.

## Scope
This change adds diagnostic observability; it does not modify the sleep scoring algorithm or assert physical parity. Native iOS CI is required.
