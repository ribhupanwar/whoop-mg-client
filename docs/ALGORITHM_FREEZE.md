# STRAP algorithm freeze

Owner directive: 2026-11-28. Accepted source baseline: `3d3d5d01f71453912b3efb37c500289976a748ed` (merged #324). This is a code-change freeze, not a runtime freeze. Automatic sleep, HRV, RHR, steps and recovery continue using live and historical observations. No clock times, metrics or thresholds may be fitted to one user's night.

## Protected behavior

- Sleep onset/backtrack, wake/resumption, staging, correction ownership/reset, lifecycle reconciliation, sleep need (8 h baseline), sleep performance and recovery.
- HRV/RHR input identity, RR quality/deduplication, coverage, timing and nocturnal measurement selection.
- Existing validated historical step counting and ledger behavior. Keep experimental live gait, optical, respiratory, SpO₂, temperature, stress, strain, VO₂ max and Healthspan work independent.

The manifest pins core source and existing regression test blobs. Shared files listed in the manifest are **review-sensitive**, not whole-file locked, to allow independent BLE, UI and sensor development. Every change to these files requires review of the protected data path and running existing native regression tests; a clean blob check alone cannot prove behavior unchanged. Do not bypass the freeze through new functions, call-site rerouting, feature flags, cache changes, dependency changes or weakening tests.

## Change policy

Only the repository owner may approve a change to protected behavior after a reproducible defect, actual diagnostic evidence, before/after replay, prior-good-night comparison and explicit approval. Document the approval and scope in the PR; never infer approval from generic merge requests or a green CI status. The frozen manifest/guard must not be modified by routine automation. An approved exception requires a separately reviewed update to the policy and pinned baseline, and the normal protocol matrix and native iOS/IPA validation. Do not disable the guard to get a green build.

## Validation

Existing native fixtures include delayed evening settling, bathroom resumption with latched state 3, stale editor saves, correction reset, replay after relaunch, preserved explicit edits, RR duration coverage and step ledger idempotence. Run the entire native suite and six protocol jobs. Use the owner's November 27–28 replay as a **private** golden reference, with correction retained and reset tested separately, plus prior successful nights. Keep exact personal timing, biometric measurements and raw captures outside the repository. The accepted replay results are owner-reported; this PR does not claim to have rerun the private native replay or validated future physical nights. A guard verifies source integrity, not biometric accuracy.

## Enforcement and limits

The algorithm-freeze CI workflow checks the exact checked-out Git tree against the manifest, and on PRs compares the manifest and guard to the base versions when present. Shared-file changes produce explicit review notices. Require the algorithm-freeze check in GitHub branch protection/rulesets, restrict bypasses and require owner review for approved exceptions. This PR does not change repository permissions or branch protection; administrators can still override or edit CI. Review-sensitive changes and newly introduced paths require human review. The policy starts when this PR merges.
