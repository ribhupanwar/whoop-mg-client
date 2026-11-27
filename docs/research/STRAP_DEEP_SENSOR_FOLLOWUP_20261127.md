# Deep sensor follow-up

Independent Swift implementations using protocol facts from NOOP 2a1de7609843b095505274ad6fc811757210be80 (PROTOCOL_SENSORS.md, ImuFeatureExtractor.swift) and OpenStrap/protocol dc699ce491c5eec4c924fafe8e29c637ea758b5a (gen5_records.dart). No upstream implementation copied. V20 is owned by #316, other route work by #315; reconcile overlapping diagnostic files rather than overwrite either branch.

- V22 v9/subversion 0: anchor and 49 signed differences reconstruct 50 raw bit patterns modulo 2^32; retain numeric channel and packed word, identify retained channels without claiming freshness; flag suffix after either exact delta rail. Other layouts remain opaque.
- V26: wide cumulative accumulator, approximate 25-code reconstruction, flag clipped-delta ambiguity and impossible ADC codes; no pulse or RR inference.
- V21: per-block acceleration magnitude variation, adjacent magnitude-change RMS and mean rotation. Preserve independent axis counts, do not derive cadence from one block. Continuous gait feature extraction needs contiguous multi-second validated timestamps.
- Existing historical diagnostics consume new summaries; no score changes. No physical capture replay or native test executed in this environment. Swift regression fixtures included; Python mirror and native CI pending. Remaining scope: R16/R17, other R22 tags, live IMU and Type51/52, validated optical pulse/respiration, SpO2 calibration, live RR stress and sleep/activity consumers. Do not represent as full completion.
