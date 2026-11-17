# Sleep preservation and recovery repair

Baseline: `origin/main` 2727b64. Isolated branch: `codex/sleep-preservation-repair-20261117`. No main merge, no PR #44 merge, no other branch changes.

## What is known, and what needs device evidence

The user's installed container was not available in this workspace. No conclusion that the previous night's sleep was deleted, survived or is recoverable can be drawn from repository inspection. Installing IPAs over an existing app is not evidence of an uninstall. The read-only export is the first device evidence to collect; do not reinstall or reset to investigate.

`BandLink.latestSleepSession` previously required `session.version == SleepSession.algorithmVersion`, while `SleepSession.retainingUncovered` retained older versions. This combination can retain a night in preferences while hiding it from screens. The equality gate originated in a87cdd7; staging recipe version 4 arrived in 7a0fd9c. This is a reproducible hiding mechanism, not proof that it caused this user's incident.

Home's activities card rendered a Sleep link unconditionally. SleepDetect allowed a >=90-minute daytime candidate with quiet on-wrist motion and a lower HR, without the sustained positive band evidence required for evening candidates. Those paths can explain a false 13:09–15:09 presentation; actual samples are required to establish the reported session's origin.

Main and rejected 26d51a4 both use `com.ribhupanwar.strap`, default UserDefaults, Application Support `strap-history-v18.sqlite` / legacy JSON, and Documents `captures`. Project signing is disabled for CI. No Team ID/provisioning profile is specified; the external IPA signer supplies the installed application identifier and team. Source settings cannot establish actual container continuity. Compare the *installed, finally signed* IPA entitlements and provisioning profiles, not just CI artifacts.

No historical row deletion, SQLite/WAL removal or preference-domain reset was found in the audited startup/archive writer paths. SQLite holds unbounded raw seconds; `recentSamples` loads only a 72-hour analysis window. Live RR preferences retain a bounded buffer. No permanent-loss claim is justified by an empty in-memory window.

## Implemented

- Read-only diagnostic ZIP: online SQLite backup includes committed WAL rows without checkpointing the source; schema, logical bounds/counts, file sizes and SHA-256, saved-record decoding/count/version inventory, original cached bytes, corrections, imports, GPS and raw captures. Authentication settings are excluded by an explicit key allowlist. Source sidecar checksums are observations, not a coherent cross-file copy.
- Append-only, content-addressed preservation before replacing/removing summary, sleep report or daily cache bytes. Undecodable previous values are retained too. Failed evidence preservation prevents the replacement.
- Explicit saved-session preview and restore with provenance, original timestamps and current manual-bound precedence. No automatic invented overnight session or biometrics. Prior summary evidence remains available for reversal.
- Recipe-version changes invalidate analysis caches, not the stored night's visibility. Daytime legacy candidates, confirmed naps and overnight sessions are distinguished; naps cannot become the night's ring/Recovery source. Daytime/evening detector candidates require sustained band-sleep evidence in addition to wear, HR and motion. Background quiet tails cannot extend a retained wake boundary without positive tail evidence.
- Invalid legacy JSON no longer marks migration complete; the original plus one hashed invalid copy remain, and later reopen can retry. Missing legacy files are not marked migrated.
- Versioned full backup: known app health/profile/settings stores, full raw SQLite, raw captures, GPS, corrections, imports and recovery evidence. All Data and Full Backup use this same complete persisted-store snapshot. Diagnostic-only exports are not accepted as backups.
- Restore preflight checks paths, duplicate entries, symlinks, extraction budgets, manifest coverage and checksums. Users review before staging. Activation occurs before app stores/BLE writers start. Missing raw seconds merge in one SQLite transaction; existing raw seconds and preference keys win. A durable startup journal plus transactional commit marker permits rollback/replay after interruption. Preference delivery is synchronized before commit. Original imported snapshot stays in `restore-history`. Conflicting existing collections are preserved, rather than silently merged or overwritten.
- WHOOP ZIP/CSV source imports are additive and content-idempotent. Original columns, timestamps/timezones, revisions and optional fields survive. An unreadable existing import fails without replacement. Date filters, source-record browsing and individual JSON export are available. HRV/RHR cycle projection prefers the wake/cycle-end date when supplied.
- Apple Health import requests explicit read authorization for HR, RHR, SDNN HRV, respiration, oxygen, steps, active energy, sleep categories and workouts. Original sample UUID/source/timestamps are retained and deduplicated. SDNN does not feed RMSSD Recovery.
- Health Monitor displays HR plus respiration, SpO2, RHR and HRV; R–R developer diagnostics moved to a separate screen. Existing timestamp-aware HR trace, grid, DIN/Proxima typography, gradient/cursor/endpoint and freshness gates are retained. Candidate oxygen is not presented as clinically validated.

## Verified WHOOP segments and limits

NOOP's actual `Packages/StrandImport/Sources/StrandImport/WhoopExportImporter.swift`, coordinator, models, exporter and tests were inspected, with dsta's relevant protocol/UI references. No NOOP implementation was copied.

| Source | Preserved/imported | Native calculation integration |
|---|---|---|
| physiological_cycles.csv | Complete original rows: Recovery, HRV/RHR, strain, energy, HR, respiration, oxygen/temperature and sleep fields when supplied | Existing HRV/RHR day projection fills gaps; other official metrics remain distinguishable source fields |
| sleeps.csv | Original windows, nap flag, performance, stage duration totals, efficiency/consistency/need/debt when supplied | Browseable source history; does not synthesize epoch stages from totals |
| workouts.csv | Original activity/window, strain/energy/HR/zones and optional distance/altitude fields | Browseable source history; not merged into local workout/strain estimates |
| journal_entries.csv | Original questions, answers, notes and cycle/timezone fields | Browseable source history; not rewritten into local journal entries |

WHOOP profile, GPS coordinate tracks and steps are not guaranteed by these four schemas. Such supplied source columns are retained, but no missing fields or route samples are invented. Full NOOP parity, localized filename/header aliases and native projection of every official metric remain incomplete. Apple Health does not import GPS routes or profile characteristics in this change.

## Validation and remaining checks

Regression coverage includes WAL snapshot consistency, credential-key exclusion, undecodable cache preservation, false daytime rest, old recipe retention, nap separation, wake-bound drift, migration retry, additive/date-filtered imports, full export/fresh-container restore/repeat import, existing-second/manual-edit precedence, corrupt-backup rejection, transaction rollback and interrupted post-commit preference delivery. Python's 287 tests passed locally; final simulator/build/archive status and IPA are reported in PR #45 after Actions completes.

Physical-device sleep recovery, overnight metric recomputation, final signer/container identity, HealthKit permission behavior, live BLE continuity and exact screenshot fidelity remain unverified. The current thread supplied no screenshot or device database. If no reliable cached session and insufficient raw evidence survive, the correct outcome is insufficient evidence, never fabricated sleep or Recovery.
