# Phase 17 — WHOOP Activity Screens Forensic Audit

**Classification:** `VERIFIED_BINARY` + `VERIFIED_ASSET` + `VERIFIED_SCREENSHOT`  
**Binary Modules:** `WhoopActivities`, `WhoopCoreDetails_WhoopAddActivity`, `WhoopCoreDetails_WhoopEditActivity`, `WhoopTrackActivity`

---

## 1. Activity Detail Screen

```
+-------------------------------------------------------------+
| < TODAY                    OUTDOOR RUNNING          [Edit]  |
+-------------------------------------------------------------+
|                                                             |
|                       [ 14.2 ]                              |
|                    ACTIVITY STRAIN                          |
|                                                             |
|   [DURATION]      [AVG HR]        [MAX HR]      [CALORIES]  |
|     48:20          152 bpm         174 bpm       642 kcal   |
|                                                             |
|   +-----------------------------------------------------+   |
|   | HEART RATE OVER TIME GRAPH                          |   |
|   | [Zone 1] [Zone 2] [Zone 3] [Zone 4] [Zone 5]        |   |
|   +-----------------------------------------------------+   |
|   | GPS ROUTE MAP (If outdoor activity)                 |   |
|   | Distance: 5.24 mi | Avg Pace: 9:14 /mi              |   |
|   +-----------------------------------------------------+   |
+-------------------------------------------------------------+
```

---

## 2. Activity List & Feed Card

- **Card Layout:** Rounded rectangular card (`#1D2429`, corner radius 12 pt).
- **Activity Icon:** Sport-specific vector icon in `#0091FF` circle (36 pt).
- **Activity Title:** `ProximaNova-Bold` 16 pt (e.g. `"Running"`, `"Cycling"`, `"Functional Fitness"`).
- **Timestamp & Duration:** `ProximaNova-Regular` 13 pt (e.g. `"Today at 7:15 AM • 45 min"`).
- **Strain Pill:** Trailing pill displaying activity strain score (e.g. `"11.8"` in `DINPro-Bold` 14 pt, blue border).
- **Swipe Actions:**
  - Swipe Left: Delete action (`#FF3B30` red background, trash can icon).
  - Tap: Opens full Activity Detail Screen.

---

## 3. Supported Sport Taxonomy (`WHPSportId` in Binary)

Extracted sport IDs and names from `WhoopActivities_WhoopActivities.bundle`:
- Running (Outdoor / Treadmill)
- Cycling (Outdoor / Stationary)
- Swimming
- Walking / Hiking
- Weightlifting / Strength Trainer
- HIIT / Functional Fitness
- Boxing / Martial Arts
- Yoga / Pilates
- Basketball / Soccer / Tennis
- Golf / Rowing / Skiing / Snowboarding
