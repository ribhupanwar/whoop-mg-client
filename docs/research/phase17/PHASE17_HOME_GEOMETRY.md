# Phase 17 — WHOOP Home Screen Geometry Forensic Extraction

**Classification:** `VERIFIED_SCREENSHOT` + `VERIFIED_BINARY`  
**Reference Screenshot:** `WhatsApp Image 2026-11-14 at 12.42.12 PM (2).jpeg` (736 x 1600 px)

---

## 1. Vertical Page Rhythm (Point Metrics)

All dimensions converted to Apple standard points (`1 pt ≈ 1.8728 px` at reference scale):

```
+-----------------------------------------------------------------+  y = 0 pt
| iOS Safe Area Top (Dynamic Island / Notch): 54.0 pt             |
+-----------------------------------------------------------------+  y = 54 pt
| HEADER REGION (Height: 44.0 pt)                                 |
| - Left: Calendar Navigation / Date ("Today", 18 pt Proxima Bold)|
| - Center: STRAP Wordmark (replaces WHOOP logo)                  |
| - Right: Battery Icon (21 pt x 10.5 pt) + Text ("85%")          |
+-----------------------------------------------------------------+  y = 98 pt
| GAP: 16.0 pt                                                    |
+-----------------------------------------------------------------+  y = 114 pt
| HERO 3-RING SCORE CARD (Height: 148.0 pt)                       |
| - Left: Sleep Ring (104 pt)                                     |
| - Center: Recovery Ring (104 pt)                                |
| - Right: Strain Ring (104 pt)                                   |
| - Inter-ring gap: 18.0 pt                                       |
+-----------------------------------------------------------------+  y = 262 pt
| GAP: 14.0 pt                                                    |
+-----------------------------------------------------------------+  y = 276 pt
| STRESS MONITOR TILE (Height: 120.0 pt)                          |
| - Status Header: "STRESS MONITOR • MEDIUM"                      |
| - Live 24-hour scrolling graph with zone bands                  |
+-----------------------------------------------------------------+  y = 396 pt
| GAP: 14.0 pt                                                    |
+-----------------------------------------------------------------+  y = 410 pt
| STRAIN & RECOVERY 7-DAY BAR CHART CARD (Height: 160.0 pt)       |
| - 7 vertical day bars with dual strain/recovery fills           |
+-----------------------------------------------------------------+  y = 570 pt
| GAP: 14.0 pt                                                    |
+-----------------------------------------------------------------+  y = 584 pt
| MY DASHBOARD SECTION                                            |
| - Section Title: "MY DASHBOARD" (14 pt Proxima Bold Uppercase)  |
| - 2-Column Grid Metric Tiles (Height: 110.0 pt each)            |
|   - HRV Tile (ms)                                               |
|   - Resting Heart Rate Tile (bpm)                               |
|   - Steps Tile                                                  |
|   - Calories Burned Tile (kcal)                                 |
+-----------------------------------------------------------------+
| FLOATING ACCESSORY ("DISCOVER MORE" Pill): 44.0 pt              |
+-----------------------------------------------------------------+
| BOTTOM TAB BAR: 56.0 pt                                         |
+-----------------------------------------------------------------+
| iOS Safe Area Bottom: 34.0 pt                                   |
+-----------------------------------------------------------------+
```

---

## 2. Horizontal Margins & Padding

- **Screen Outer Margin:** `16.0 pt` on both leading and trailing edges.
- **Card Content Width:** `screenWidth - 32.0 pt` (`361.0 pt` on iPhone 14/15 Pro).
- **Inter-Tile Horizontal Spacing:** `12.0 pt`.
- **Card Internal Padding:** `16.0 pt` (all sides).
- **Card Corner Radius:** `12.0 pt`.
