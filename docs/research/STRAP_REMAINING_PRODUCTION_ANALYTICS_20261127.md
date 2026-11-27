# Remaining production analytics batch
Base f36fa618. Coordinate with #316 (V20), #318 (deep decoding and IMU evidence), #319 (sleep correctness). This PR implements independent, bounded live RR source coverage and canonical-before-gate stress replay selection. Native/standard live samples are kept separate, actual receipt seconds are not beat time, no score from unmatched motion/contact. Existing raw archive stays lossless. Tests cover source collision, invalid padding, gaps, freshness and conflicting replay. No estimator calibration changed.

## Explicit outstanding acceptance gates
- V21 sleep and activity production integration: align native IMU windows with canonical V18 timestamps; avoid replacing validated motion with unrelated RMS. Require real paired night/workout fixtures before changing scores. #318 rhythm remains diagnostic.
- V18 optical HRV filtering: retain raw pSNR and selected source; no accepted threshold or physical validity yet. Evaluate shadow windows before gating.
- V20 optical pulse detection: #316 owns actual decoder; independent channel identity, contiguous sample time and pulse oracle required. V26 rail-clipped suffix cannot provide valid NN.
- Respiration optical fusion: independent intensity estimate requires calibrated/identified channel, motion and timing; no simulated vital signs.
- SpO2: encoding, burst coverage and independent oximeter agreement unresolved. Never enable candidate as validated measurement.
- R17 HRV word: spot ECG raw value is not overnight RMSSD; units and applicability unverified.
- Type51/52 and Rev10: exact firmware shape, validated boundary and units needed; never force existing decoder onto unknown route.
- Live stress: source-separated evidence is implemented; actual score requires trustworthy aligned motion/wrist/awake context and beat identity. Baseline and existing score gates unchanged.
- Physical replay and native CI remain required. This PR does not close #214 or #252 or claim the outstanding areas are implemented.