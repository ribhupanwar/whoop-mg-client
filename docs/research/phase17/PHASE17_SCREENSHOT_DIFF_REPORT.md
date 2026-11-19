# Phase 17 — Screenshot Visual Diff & Forensic Discrepancy Report

**Reference Dataset:** 67 Screenshots (`Downloads/UI`, `HEALTH`, `ROCOVERY`, `SELEEP`, `STAIN`, `STRAP`)  
**Target Device Resolution:** 736 x 1600 px (Scaled iPhone 14/15 Pro)

---

## 1. Home Screen Forensic Comparison

| Component | WHOOP Reference Measurement | Current STRAP Implementation | Pixel Delta / Discrepancy | Required Correction | Priority |
|---|---|---|---|---|---|
| **Canvas Background** | LinearGradient `#273037` to `#101518` | Top `#253038`, Bottom `#121518` | Minimal (<2% RGB delta) | Align top hex to `#273037` | P1 |
| **Score Rings Diameter** | `104.0 pt` (`160 px` scaled) | Variable (`104 pt` provisional) | ~2 pt stroke padding | Ensure exact 104 pt outer boundary | P0 |
| **Score Rings Stroke** | `8.0 pt` | `8.0 pt` | Exact match | Preserved | P0 |
| **Inter-Ring Spacing** | `18.0 pt` | `18.0 pt` | Exact match | Preserved | P0 |
| **Score Numbers Typography**| `DINPro-Medium` 24 pt | Proxima Nova / System Font | Font mismatch | Switch score digits to `DINPro-Medium` | P0 |
| **Battery Indicator Width** | `21.0 pt` | SF Symbol `battery.100` (~25 pt) | +4 pt too wide, wrong shape | Replace with custom vector pill | P0 |
| **Bottom Tab Bar Height** | `56.0 pt` | Custom navigation bar | ~4 pt delta | Set frame height to exactly `56 pt` | P0 |
| **Above-Tab Accessory** | `"DISCOVER MORE"` Floating Pill | Missing / Static text | Element omitted | Add floating capsule button | P0 |
| **Health Monitor Card** | 5 tiles with status dots | 3 tiles with placeholder | Missing Respiratory/Temp rows| Implement full 5-metric table | P1 |
| **Stress Monitor Tile** | 24-hr live line chart | Static "Unavailable" | Missing live trace renderer | Port Stress live graph | P1 |

---

## 2. Typography & Color Parity Summary

1. **Numeric Font Parity:** STRAP previously used Proxima Nova for several numerical outputs. WHOOP strictly utilizes **DIN Pro** (`DINPro-Bold`, `DINPro-Medium`, `DINPro-Regular`) for all scores, metrics, percentages, and timestamps.
2. **Ring Track Translucency:** WHOOP background tracks use `20%` opacity of the primary zone color. STRAP's previous tracks were slightly too opaque (~30%).
3. **Tab Bar Material:** WHOOP applies `systemUltraThinMaterialDark` with `#171E22` tint. STRAP must ensure proper background translucency.
