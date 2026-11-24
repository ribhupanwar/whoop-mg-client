# Real Data Validation — 2026-11-24

## Production commit
- main HEAD: eeffa9b868457d11a8e0646b4b5c59e49f7ec1cd (at validation start)
- Sleep PR #212 HEAD: af3050a (after HRV reconciliation)

## Data inventory
- research-inputs/sleep-...csv: 26,580 rows, unique seconds 26,580, range 1795455187..1795481767 (2026-11-23 17:33:07 UTC .. 2026-11-24 00:56:07 UTC)
- Recovery JSON: archiveSampleCount 24,780, archiveFirstUnix 1795456987, archiveLastUnix 1795481767 (window 1795456987..1795481768)
- CSV contains 1,800 extra seconds before archive window start (1795455187 vs 1795456987) and 26,580 total vs 24,780 archived.

## 24 Nov comparison
| Metric | WHOOP | STRAP CSV tail |
| Sleep start | 11:33 PM | 11:33 PM (1795456987) |
| Sleep end | 6:38 AM | 6:26 AM (1795481767) |
| Difference | +12 min | archive ends 12 min early |

## Root cause (evidence)
CSV/recovery archive last unix = 1795481767 = 00:56:07 UTC. With local offset +5:30 this is 06:26:07 local, matching STRAP 6:26. WHOOP 6:38 implies 12 additional minutes of records not present in the archive. This is a data-cutoff/sync-completeness issue, not an end-of-sleep detector error. Do not retune sleep algorithm.

## Tests run
- python -m pytest -q: 421 passed, 1 skipped (run 2026-11-24)
- iOS XCTest not executable on Windows; CI pending for HEAD af3050a.

## Unresolved
- Physical-band capture of the missing 12-min tail needed to confirm detector.
- Swift production replay requires macOS runner.
