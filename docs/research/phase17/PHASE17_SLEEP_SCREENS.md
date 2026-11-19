# Phase 17 — WHOOP Sleep Screens Forensic Audit

**Classification:** `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT`  
**Binary Modules:** `WhoopCoreDetails_WhoopSleepDetails`, `WhoopSleepCoach`, `WhoopDeepDive_WhoopDeepDiveSleep`

---

## 1. Sleep Performance Screen Layout

```
+-------------------------------------------------------------+
| < TODAY                        SLEEP                        |
+-------------------------------------------------------------+
|                                                             |
|                       [ 80% ]                               |
|                  HOURS OF SLEEP                             |
|                      6:42 hr                                |
|                                                             |
|   +-----------------------------------------------------+   |
|   | HOURS VS. NEEDED                                    |   |
|   | 6:42 / 8:20 hr (80%)                                |   |
|   +-----------------------------------------------------+   |
|   | SLEEP EFFICIENCY                                    |   |
|   | 92% (Time in Bed: 7:18 hr)                          |   |
|   +-----------------------------------------------------+   |
|   | RESTORATIVE SLEEP                                   |   |
|   | 3:14 hr (Deep SWS 1:42 + REM 1:32)                  |   |
|   +-----------------------------------------------------+   |
|   | SLEEP STAGES HYPNOGRAM                              |   |
|   | [Awake] [Light] [REM] [Deep]                        |   |
|   +-----------------------------------------------------+   |
+-------------------------------------------------------------+
```

---

## 2. Sleep Stages Hypnogram Specifications

The hypnogram is rendered as a multi-tier timeline with 4 stacked stage bands:

| Stage Name | Color Hex | Band Height | Stack Position | Meaning |
|---|---|---|---|---|
| **Awake** | `#FF6666` | `10.0 pt` | Top Tier (Level 4) | Wake periods, brief arousals |
| **Light Sleep** | `#3075A6` | `10.0 pt` | Mid-Upper (Level 3) | Stage N1 & N2 sleep |
| **REM Sleep** | `#A663CC` | `10.0 pt` | Mid-Lower (Level 2) | Rapid Eye Movement sleep |
| **Deep Sleep (SWS)** | `#1A4366` | `10.0 pt` | Bottom Tier (Level 1) | Slow Wave / restorative physical sleep |

### Hypnogram Metrics & Legend
- **Timeline Range:** Bedtime (e.g. 10:45 PM) to Wake time (e.g. 6:30 AM).
- **Time In Bed Card:** Displays Bedtime, Wake Time, Total Asleep Time, Disturbances count.
- **Stage Percentage Bar:** Horizontal segmented stacked progress bar showing:
  - Deep % (`DINPro-Medium` 14 pt, Deep Navy)
  - REM % (`DINPro-Medium` 14 pt, Lavender)
  - Light % (`DINPro-Medium` 14 pt, Medium Blue)
  - Awake % (`DINPro-Medium` 14 pt, Coral Red)

---

## 3. Sleep Coach & Need Calculation (`WhoopSleepCoach`)

- **Sleep Need Gauge:**
  - Baseline Sleep Need (e.g. 7:45 hr)
  - `+` Recent Strain Need (e.g. +0:35 hr)
  - `+` Sleep Debt (e.g. +0:42 hr)
  - `-` Nap Credit (e.g. -0:30 hr)
  - `=` Total Sleep Need (e.g. 8:32 hr)
- **Wake Alarm Settings:**
  - Slider wake time control with haptic alarm preview.
  - Modes: `"Exact Time"`, `"Sleep Goal (85% / 100%)"`, `"In The Green (Recovery > 66%)"`.
