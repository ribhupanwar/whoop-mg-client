# Woop IPA feature/layout audit

Source: user-supplied iOS.zip, Woop-ios-unsigned-4a3ef0e.ipa, SHA-256 3f06fe8b24a36861a92553ea27e9bbe949fabfd8d7d566dc7dbca37894c31c5c. Static string inventory and archive member inspection, not executable UI screenshots. No bundled executable, fonts, artwork or third-party source copied.

| IPA evidence | STRAP baseline | Decision |
|---|---|---|
| Home / Health / Sleep / Community / More | RootView has four approved tabs: Home, Health, Humans, More | Preserve four; expose existing Sleep Planner, Journal and Plan via More. |
| HEALTH & ACTIVITY, activity and journal settings | Existing JournalView, PlanView, SleepCoachView | Add real navigation links, no fake features. |
| Home Screen Widgets, Liquid Glass & Solid styles | StrapWorkoutWidgetBundle contains workout Live Activity, captured steps Live Activity and captured steps Home widget | Add discoverability page; recovery/strain/sleep/battery widget not established in current bundle. Follow-up needs shared snapshot, privacy and WidgetKit tests. |
| Measurement system, Reduce glass transparency, iPhone permissions | RootView appearance mode; AppPreferencesView fixed metric units; NotificationSettingsView permissions | Expose existing System/Light/Dark state in More. Do not claim alternate units or glass toggle are implemented. |
| Import and merge backup; portable .woop/.noopbak formats | Existing WHOOP import and STRAP backup/restore | Preserve local archive; portable format needs schema/licensing and merge tests. |
| CURRENT, STALE, ACTIVITY, movement excluded; measured time only | StressWindows/StressView | Gap-aware RR calculation and missing coverage rendering in this PR; movement-aware baseline and true live stress still research. |
| Resting HR alerts, emergency contact, cloud account, community sharing | Local-first STRAP architecture | Not copied or silently enabled; alerts need separate sensor validation and consent; cloud/social features require explicit scope. |
| Sleep Planner, detected naps and daily behaviors | Existing sleep and journal paths | Add discovery, assess nap parity and journal correlations separately on fixtures. |

Release acceptance: exact-head iOS and protocol CI; actual device screenshots across tabs in dark/light and Dynamic Type; verify navigation destinations, back button, safe areas, widgets on signed install. No pixel parity, physical sensor calibration or feature equivalence claim from binary strings alone.
