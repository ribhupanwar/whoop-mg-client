# Additional Woop IPA adoption review (2026-11-27)

Source: supplied iOS(1).zip, executable string inventory and bundled WoopEngine-NOTICE.txt. These strings establish visible feature intent, not runtime behavior or algorithms.

| Woop evidence | STRAP comparison at a6499f7 | Adoption decision |
|---|---|---|
| Finish activity / Discard activity / Save your recorded activity or keep recording | GPSRunView wraps its TimerHeader Button in a full-height VStack with allowsHitTesting(false), disabling the button that opens Pause/Resume/End controls | Replace with a header-only overlay; verify swipe navigation and dialog actions on device |
| Keep live workout metrics visible while recording; screen sleeps normally after leaving workout | No idle-timer setting in GPSRunView | Candidate: opt-in, scoped foreground idle-timer ownership and restoration on pause/end/navigation/background; needs lifecycle test |
| Review suggested activities before saving; Check recent activity | STRAP has existing activity detection and manual history | Candidate: opt-in review mode, avoid silently replacing automatic detection |
| Customize journal; 5 yes and 5 no answers for comparison; journal reminder | Existing local JournalView and journal correlations | Candidate: configurable questions, minimum group sizes, local reminder; distinguish unanswered from No and validate fixtures |
| Band battery alerts; recovery/sleep recap; workout summaries | NotificationSettingsView handles authorization and wake-alarm links | Candidate: opt-in local notifications with dedup, stale-data suppression and consent |
| Apple Health export of new readings; import workouts from other apps | HealthKitBridge has workout export, profile import and category authorization; authorization alone does not publish metrics | Candidate: separate validated per-metric export/import paths and dedup |
| Stress excludes exercise, post-exercise recovery and off-body intervals; missing RR stays unknown | Existing #285 stress coverage work | Validate movement-aware personal baseline and post-workout suppression; no HR-only measured stress claim |
| Portable .woop/.noopbak/.sqlite backup formats | Existing #285 portable backup inspection | Schema and bounded archive validation before implementing non-destructive import |
| Coach provider selection and selective context | Existing StrapAICoachView provider and snapshot consent | Candidate: per-category sharing and local conversation memory with explicit deletion |
| Guided breathing and optional sessions | No dedicated breathing view identified in tree inventory | Candidate: local timer, optional, no claim of measured stress improvement |
| Battery saver preserving pairing; band/charging guidance | Existing device controls and pair view | Candidate: non-destructive explicit disconnect and charging guidance; no unsafe command experiments |

Bundled notice identifies NOOP engine original work as PolyForm Noncommercial 1.0.0; dependencies retain separate terms. Implement original code, do not copy source or assets without license review. Cloud/community/emergency contact features are not automatic adoption targets.

Validation: header hit-test defect confirmed by static source inspection; native simulator/device interaction, exact-head protocol and iOS CI are still required. No physical sensor calibration or screenshot parity established.
