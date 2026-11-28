# Split-sleep presentation evidence — 2026-11-28

The supplied 5.80.2 report identifies removeRecoveryAndSleepFromCycleDict and a six-hour comparison. Its reported conditional call chain is not independently replayed here; an open physiological cycle, ongoing BLE sync and an incomplete sleep window are not interchangeable. No general short-sleep threshold is adopted. No WHOOP JSON or native split flag is consumed.

At main a842e11579265881484244c759682a9e8ae1378e, SleepLifecycleSnapshot is defined in AppStore.swift, not State/SleepLifecycleSnapshot.swift. It has no isSplitSleepInProgress property. HomeView omitted the provisionalWake phase from the sleep card.

This presentation-only notice reads the existing provisionalWake state, matches the latest unedited overnight session, and is limited to today's Home in live mode. It labels existing values provisional; it does not hide or delete measurements, modify wake transitions or require six hours of sleep. A completed five-hour night retains the ordinary presentation. No sync timer or three-hour freshness rule is added. Tests cover the pure UI predicate and existing lifecycle transitions; native CI and real-device observation still required.
