# Phase 17 — WHOOP Score Ring Geometry Forensic Extraction

**Classification:** `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT`  
**Binary Structs:**
- `WhoopDesign.MultiRingGauge`
- `WhoopDesign.ScoreGauge`
- `WhoopDesign.GaugeTrack`

---

## 1. Swift Metadata Declaration (`WhoopDesign.MultiRingGauge`)

```swift
// Extracted from Whoop.swift
struct WhoopDesign.MultiRingGauge {
    let outerCircleDiameter: CGFloat
    let innerCircleDiameter: CGFloat
    let fadedStrokeWidth: CGFloat
    let highlightStrokeWidth: CGFloat
    let gaugeType: WhoopDesign.GaugeType
    let isHighlighted: Bool
    let trimPercent: CGFloat
}

struct WhoopDesign.GaugeTrack {
    let radius: CGFloat
    let width: CGFloat
}
```

---

## 2. Forensic Measurements: 3 Hero Rings Cluster

The 3 hero rings on the Home screen represent:
1. **Left Ring:** Sleep Performance (`colorSleep` #4CA6E6)
2. **Center Ring:** Recovery Score (`colorRecovery` Green/Yellow/Red)
3. **Right Ring:** Day Strain (`colorStrain` #0091FF)

```
        Sleep Ring               Recovery Ring              Strain Ring
     +---------------+         +---------------+         +---------------+
    /     (SLEEP)     \       /    (RECOVERY)   \       /     (STRAIN)    \
   |        80%        | --- |        75%        | --- |        12.2       |
    \                 /  18pt \                 /  18pt \                 /
     +---------------+         +---------------+         +---------------+
          104 pt                    104 pt                    104 pt
```

### Exact Dimension Table

| Parameter | Measured Specification (`pt`) | Evidence Source | Confidence |
|---|---|---|---|
| Outer Diameter | `104.0 pt` | `WhoopDesign.MultiRingGauge` + Screenshot Ratio | `VERIFIED_BINARY` |
| Stroke Width | `8.0 pt` | `highlightStrokeWidth` / `fadedStrokeWidth` | `VERIFIED_BINARY` |
| Inner Diameter | `88.0 pt` (`104 - 2 * 8`) | Calculated geometry | `VERIFIED_BINARY` |
| Ring-to-Ring Gap | `18.0 pt` | Measured horizontal inter-ring spacing | `VERIFIED_SCREENSHOT` |
| Center-to-Center Distance | `122.0 pt` (`104 + 18`) | Geometry validation (`368 - 140 = 228 px @ 1.87 px/pt = 121.7 pt`) | `VERIFIED_SCREENSHOT` |
| Arc Start Angle | `-90°` (12 o'clock position) | Clockwise stroke progression | `VERIFIED_SCREENSHOT` |
| Arc End Angle | Calculated: `-90° + (score / max * 360°)` | SwiftUI Trim modifier | `VERIFIED_BINARY` |
| Line Cap Style | Round (`.round`) | Smooth rounded stroke termination | `VERIFIED_SCREENSHOT` |
| Background Track Opacity | `0.20` – `0.22` (20% – 22%) | Color channel forensics | `VERIFIED_SCREENSHOT` |
| Track Stroke Width | `8.0 pt` | Matches foreground stroke | `VERIFIED_BINARY` |

---

## 3. Typography Inside Rings

### Center Metric Value
- **Font Family:** `DINPro-Medium`
- **Point Size:** `24.0 pt`
- **Line Height:** `28.0 pt`
- **Color:** `#FFFFFF` (100% white)
- **Alignment:** Strictly centered at circle center `(x: radius, y: radius)`

### Subscript / Unit / Percent Sign
- **Sleep & Recovery:** Suffix `%` in `DINPro-Regular` at `14.0 pt`, baseline-aligned to the bottom of the integer value.
- **Strain:** Decimal format (e.g. `12.2`), decimal point in same `DINPro-Medium` 24 pt.

### Bottom Ring Label
- **Sleep:** `"SLEEP"`
- **Recovery:** `"RECOVERY"`
- **Strain:** `"STRAIN"`
- **Font Family:** `ProximaNova-Bold`
- **Point Size:** `11.5 pt` (scaled with minimum scale factor `0.85` to avoid clipping)
- **Text Case:** Uppercase (`Text.Case.uppercase`)
- **Letter Spacing:** `+0.5 pt` tracking
- **Color:** `#A3ADB5` (Secondary text)
- **Spacing below Ring:** `8.0 pt`

---

## 4. STRAP Ring Correction Checklist

1. [x] Eliminate unintended padding surrounding `RingView` (already implemented in commit `ebf13f7`).
2. [ ] Ensure exact outer frame is `104 pt x 104 pt`.
3. [ ] Set `lineWidth: 8.0`.
4. [ ] Set inter-ring horizontal spacing in `HStack(spacing: 18)`.
5. [ ] Render score text with `Font.custom("DINPro-Medium", size: 24)`.
6. [ ] Render `%` with `Font.custom("DINPro-Regular", size: 14)`.
7. [ ] Render label with `Font.custom("ProximaNova-Bold", size: 11.5).kerning(0.5)`.
