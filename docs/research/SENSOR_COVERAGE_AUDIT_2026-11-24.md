# Sensor Coverage Audit — 2026-11-24

## CSV (sleep-...csv)
- Rows: 26,580 data, all unique seconds (no duplicates).
- Window: 1795455187..1795481767.
- HR coverage: all rows have heart_rate_bpm.
- RR: rr_ms present; some rows multiple intervals pipe-separated.
- Accel/gravity: present on all rows.

## Archive (recovery JSON)
- archiveSampleCount: 24,780
- archiveFirstUnix: 1795456987 (1,800s after CSV first)
- archiveLastUnix: 1795481767 (matches CSV last)
- Gap: CSV has 1,800 pre-archive seconds (17:33:07..18:03:06 UTC) not in archive.

## Conclusion
- Sleep end discrepancy (12 min) is due to archive ending at 06:26 local; WHOOP extends to 06:38. Need complete BLE sync / full capture to validate end-of-sleep detector.
- No duplicate seconds; no missing within archive range (24,780 contiguous seconds).
