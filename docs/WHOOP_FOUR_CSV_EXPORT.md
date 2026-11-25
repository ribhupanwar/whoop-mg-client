# WHOOP-style four-CSV export — #248

Output archive at ZIP root: `physiological_cycles.csv`, `sleeps.csv`, `workouts.csv`, `journal_entries.csv`. Keep existing STRAP full backup unchanged.

Sources: locally measured cycle HRV/RHR, sleep records, workouts and user journal entries. Do not present WHOOP-imported records as STRAP measurements. Preserve provenance; never fabricate missing fields. Empty categories require a valid header-only CSV. RFC-4180 CSV quoting, UTC timestamps with documented zone, stable ordering, deterministic dedup, date ranges, round-trip tests and explicit compatibility caveat until verified with a real WHOOP export.

Production integration: new ZIP writer, share-sheet entry in `ios/Strap/MoreDetailViews.swift`, regression tests, exact-head iOS build-test-ipa. This document defines acceptance criteria, not finished implementation.
