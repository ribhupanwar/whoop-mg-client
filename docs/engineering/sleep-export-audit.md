# Timestamp-aligned sleep export audits

`tools/analyze_sleep_export.py` is read-only and uses Python's standard library.
It reproduces the current quiet-window RHR selection and gap-aware RR RMSSD,
reports stored stage labels, and explicitly accounts for missing prefix/tail data.
It does **not** infer WHOOP stages or re-stage the night. Example:

```sh
python tools/analyze_sleep_export.py /path/to/sleep.csv \
  --timezone Asia/Kolkata \
  --reference-start 2026-11-16T23:28:00+05:30 \
  --reference-end 2026-11-17T07:32:00+05:30 > /path/to/private-report.json
```

ISO bounds require an offset. Unix timestamps are absolute instants; changing
presentation timezone must not shift the underlying sensor samples. Bounds are
half-open. Duplicate seconds are rejected instead of silently choosing a packet.
Do not commit personal CSVs or generated reports to the repository.

## Verified staging defect and fix

Previously `SleepStager.respRegularity` interpolated its 4-Hz tachogram from the
first beat to the last, even when RR packets/seconds were missing in between.
HR can remain available during a long RR dropout. The interpolated ramp is not
measured respiration; its spectral peakedness then biases deep/REM emissions.

Version 4 splits respiratory input at missing RR-bearing seconds and selects
the longest usable contiguous fragment. Fragment beat order, minimum beat gate,
DFT band, stage emissions and HMM weights remain unchanged. If no fragment is
usable, the respiratory feature remains absent. HR epochs are not declared
missing merely because their RR feature is absent. A true missing second and
an empty RR packet both break interpolation; short separate fragments cannot
pool beats across a gap to pass the feature's quality gate.

This is a missing-data correctness fix, not evidence of improved agreement
with WHOOP or PSG. No stage percentage, RHR offset or HRV scaling is fitted to a
reference screenshot. RR quality flag bit meanings remain unspecified; they
must not become physiological exclusion rules without protocol evidence.

The algorithm version and analysis-cache recipe advance. Prior-version
canonical sleep sessions and manual bounds are retained under partial coverage;
complete available data can refresh an edited night without changing its bounds.
Older raw health records are not deleted. Regression tests cover these upgrade
paths and respiratory gap/fragment invariants.

## Limits of a clipped sleep CSV

A CSV beginning after a reference sleep onset cannot establish the earlier
onset or reconstruct the missing interval. Investigate detection with a retained
sensor export spanning at least an hour before both starts and an hour after
both ends, including HR, RR, dynamic acceleration, gravity, band state and UTC
Unix timestamps. A timestamped WHOOP stage timeline and its metric provenance
are needed to localize stage disagreement; WHOOP totals alone cannot establish
which algorithm mislabeled a particular epoch. Raw optical/quality diagnostics
are needed before interpreting quality-bit values or declaring low HR invalid.
