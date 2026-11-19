# Phase 17 — WHOOP Typography Forensic Audit

**Classification:** `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT`  
**Binary Struct:** `WhoopDesign.Typography` & `WhoopDesign.TextStyle` (`Whoop.swift:25986923`)

---

## 1. Font Family Allocation

The WHOOP application strictly allocates font families according to metric type and semantic hierarchy:

1. **DIN Pro (`FontFamily.dinPro`)**:
   - Solely used for numeric values, percentages, units of time (hours, minutes), and graph axes.
   - Weights observed in binary metadata:
     - `DINPro-Bold` (`dinProWithWeight:size:` at `1093cbaa6`)
     - `DINPro-Medium`
     - `DINPro-Regular`
   - Characteristics: Clean geometric DIN grotesque sans-serif with tall x-height, monospaced digits designed for high-density tabular and dashboard readability.

2. **Proxima Nova (`FontFamily.proximaNova`)**:
   - Used for all interface text: screen headings, card titles, section labels, body descriptions, button titles, and tab bar labels.
   - Weights observed in binary metadata:
     - `ProximaNova-Bold`
     - `ProximaNova-Semibold`
     - `ProximaNova-Medium`
     - `ProximaNova-Regular`
     - `ProximaNova-Light`
     - `ProximaNova-Black`
   - Characteristics: Premium modern humanist sans-serif with subtle geometric proportions.

3. **Readex Pro (`FontFamily.readexPro`)**:
   - Used for right-to-left localization (Arabic). Does not affect standard Latin / English interface.

---

## 2. Text Style Forensic Registry (`WhoopDesign.TextStyle`)

Every typography instance in `WhoopDesign` implements the following exact Swift layout contract:

```swift
struct WhoopDesign.TextStyle {
    let id: UUID
    let family: WhoopDesign.TextStyle.FontFamily
    let weight: WhoopDesign.TextStyle.Weight
    let size: CGFloat
    let lineHeight: CGFloat
    let opacity: Double
    let declaredKerning: Double
    let textCase: Text.Case?
}
```

### Forensic Mapping Table

| Style Token | Font Face | Weight | Size | Line Height | Tracking/Kerning | Case | Target UI Usage |
|---|---|---|---|---|---|---|---|
| `h1` | Proxima Nova | Bold | 28 pt | 34 pt | -0.2 | None | Primary View Header ("Today", "Overview") |
| `h2` | Proxima Nova | Bold | 24 pt | 30 pt | -0.1 | None | Modal / Sheet Title |
| `h3` | Proxima Nova | Semibold | 20 pt | 26 pt | 0.0 | None | Primary Section Title ("Stress Monitor") |
| `h4` | Proxima Nova | Semibold | 18 pt | 24 pt | 0.0 | None | Card Headline ("Strain & Recovery") |
| `h5` | Proxima Nova | Bold | 16 pt | 22 pt | 0.1 | Uppercase | Subsection Headline ("SLEEP EFFICIENCY") |
| `h6` | Proxima Nova | Bold | 14 pt | 18 pt | 0.2 | Uppercase | Eyebrow Header ("MY DASHBOARD") |
| `t1` | Proxima Nova | Semibold | 16 pt | 22 pt | 0.0 | None | Key List Item Title |
| `t2` | Proxima Nova | Medium | 15 pt | 20 pt | 0.0 | None | Standard Row Title |
| `t3` | Proxima Nova | Medium | 14 pt | 18 pt | 0.0 | None | Compact Row Title |
| `t4` | Proxima Nova | Regular | 13 pt | 17 pt | 0.0 | None | Sub-title Row Label |
| `sh1` | Proxima Nova | Medium | 15 pt | 20 pt | 0.0 | None | Header Sub-caption |
| `sh2` | Proxima Nova | Regular | 14 pt | 18 pt | 0.0 | None | Explainer Secondary Text |
| `sh3` | Proxima Nova | Regular | 13 pt | 17 pt | 0.0 | None | Footnote Subheading |
| `sh4` | Proxima Nova | Regular | 12 pt | 16 pt | 0.0 | None | Small Explainer |
| `sh5` | Proxima Nova | Regular | 11 pt | 15 pt | 0.0 | None | Micro Explainer |
| `b1` | Proxima Nova | Regular | 16 pt | 22 pt | 0.0 | None | Article Body Text |
| `b2` | Proxima Nova | Regular | 14 pt | 20 pt | 0.0 | None | Standard Card Body Text |
| `b3` | Proxima Nova | Regular | 13 pt | 18 pt | 0.0 | None | Compact Modal Body Text |
| `b4` | Proxima Nova | Regular | 12 pt | 16 pt | 0.0 | None | Secondary Caption Text |
| `b5` | Proxima Nova | Medium | 11 pt | 15 pt | 0.1 | Uppercase | Badge / Tag Text |
| `btL` | Proxima Nova | Bold | 16 pt | 22 pt | 0.1 | Uppercase | Primary Action Button ("START ACTIVITY") |
| `btM` | Proxima Nova | Bold | 14 pt | 18 pt | 0.1 | Uppercase | Secondary Button ("DISCOVER MORE") |
| `btS` | Proxima Nova | Semibold | 12 pt | 16 pt | 0.1 | Uppercase | Compact Action Button |
| `n1` | DIN Pro | Bold | 48 pt | 52 pt | -0.5 | None | Large Ring Metric Score (e.g. "80%") |
| `n2` | DIN Pro | Bold | 36 pt | 40 pt | -0.4 | None | Card Primary Metric Value (e.g. "1,930") |
| `n3` | DIN Pro | Bold | 28 pt | 32 pt | -0.3 | None | Sleep Duration (e.g. "7:24") |
| `n4` | DIN Pro | Medium | 24 pt | 28 pt | -0.2 | None | Ring Center Score in 3-Ring Cluster |
| `n4_5` | DIN Pro | Medium | 22 pt | 26 pt | -0.1 | None | Metric Intermediate |
| `n5` | DIN Pro | Medium | 20 pt | 24 pt | -0.1 | None | Tile Value (e.g. "36 ms", "52 bpm") |
| `n5_5` | DIN Pro | Medium | 18 pt | 22 pt | 0.0 | None | Secondary Tile Value |
| `n6` | DIN Pro | Medium | 16 pt | 20 pt | 0.0 | None | Small Metric / Time In Bed |
| `n7` | DIN Pro | Regular | 14 pt | 18 pt | 0.0 | None | Chart Time Axis (e.g. "12:00 AM") |
| `n8` | DIN Pro | Regular | 12 pt | 16 pt | 0.0 | None | Compact Axis Label |
| `n9` | DIN Pro | Regular | 11 pt | 14 pt | 0.0 | None | Micro Timeline Tick Label |
| `n10` | DIN Pro | Regular | 10 pt | 12 pt | 0.0 | None | Minute Tick Label |
| `numerical1000` | DIN Pro | Black | 64 pt | 68 pt | -1.0 | None | Milestone / 1000-Day Streak Display |

---

## 3. Preserved Licensed Font Assets in STRAP

STRAP already integrates licensed Proxima Nova and DIN Pro fonts in `ios/Strap/Theme.swift`:
- `ProximaNova-Regular.otf`
- `ProximaNova-Medium.otf`
- `ProximaNova-Semibold.otf`
- `ProximaNova-Bold.otf`
- `DINPro-Regular.otf`
- `DINPro-Medium.otf`
- `DINPro-Bold.otf`

**Execution Directive:** Maintain the font resolution pipeline in `Theme.swift` and map all SwiftUI views strictly to the `Typography` tokens defined above.
