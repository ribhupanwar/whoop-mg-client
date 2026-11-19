# Phase 17 — WHOOP Centralized Design Token Specification

**Originating Binary Modules:** `WhoopDesign`, `WhoopDesignModels`, `WhoopStyle`  
**Classification:** `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT`  
**Target File for STRAP:** `ios/Strap/Theme.swift` / `ios/Strap/Components.swift`

---

## 1. Typography Tokens (`WhoopDesign.Typography`)

```swift
// Evidence: Whoop.swift line: enum WhoopDesign.TextStyle.FontFamily
public enum StrapFontFamily {
    case proximaNova
    case dinPro
}

// Evidence: Whoop.swift line: enum WhoopDesign.TextStyle.Weight
public enum StrapFontWeight {
    case regular    // 400
    case light      // 300
    case medium     // 500
    case semibold   // 600
    case bold       // 700
    case black      // 900
}
```

### Hierarchy Mappings

| Token Name | Family | Weight | Point Size (`pt`) | Line Height (`pt`) | Letter Spacing (`declaredKerning`) | Text Case | Typical Usage |
|---|---|---|---|---|---|---|---|
| `Typography.h1` | Proxima Nova | Bold | 28 | 34 | -0.2 | Default | Primary Screen Headers |
| `Typography.h2` | Proxima Nova | Bold | 24 | 30 | -0.1 | Default | Modal / Card Headers |
| `Typography.h3` | Proxima Nova | Semibold | 20 | 26 | 0.0 | Default | Section Headers |
| `Typography.h4` | Proxima Nova | Semibold | 18 | 24 | 0.0 | Default | Card Titles |
| `Typography.h5` | Proxima Nova | Bold | 16 | 22 | 0.1 | Uppercase | Sub-section Headers |
| `Typography.h6` | Proxima Nova | Bold | 14 | 18 | 0.2 | Uppercase | Eyebrow Headers |
| `Typography.t1` | Proxima Nova | Semibold | 16 | 22 | 0.0 | Default | Prominent Labels |
| `Typography.t2` | Proxima Nova | Medium | 15 | 20 | 0.0 | Default | List Titles |
| `Typography.t3` | Proxima Nova | Medium | 14 | 18 | 0.0 | Default | Secondary List Titles |
| `Typography.t4` | Proxima Nova | Regular | 13 | 17 | 0.0 | Default | Caption Titles |
| `Typography.b1` | Proxima Nova | Regular | 16 | 22 | 0.0 | Default | Body Primary |
| `Typography.b2` | Proxima Nova | Regular | 14 | 20 | 0.0 | Default | Body Standard |
| `Typography.b3` | Proxima Nova | Regular | 13 | 18 | 0.0 | Default | Body Compact |
| `Typography.b4` | Proxima Nova | Regular | 12 | 16 | 0.0 | Default | Caption / Footnote |
| `Typography.b5` | Proxima Nova | Medium | 11 | 15 | 0.1 | Uppercase | Micro / Tag Labels |
| `Typography.n1` | DIN Pro | Bold | 48 | 52 | -0.5 | Default | Hero Score (Sleep/Recovery/Strain) |
| `Typography.n2` | DIN Pro | Bold | 36 | 40 | -0.4 | Default | Large Metric Value |
| `Typography.n3` | DIN Pro | Bold | 28 | 32 | -0.3 | Default | Medium Metric Value |
| `Typography.n4` | DIN Pro | Medium | 24 | 28 | -0.2 | Default | Ring Center Score |
| `Typography.n5` | DIN Pro | Medium | 20 | 24 | -0.1 | Default | Tile Number Display |
| `Typography.n6` | DIN Pro | Medium | 16 | 20 | 0.0 | Default | Table Metric Value |
| `Typography.n7` | DIN Pro | Regular | 14 | 18 | 0.0 | Default | Timestamp / Axis Number |
| `Typography.n8` | DIN Pro | Regular | 12 | 16 | 0.0 | Default | Compact Timestamp |
| `Typography.n9` | DIN Pro | Regular | 11 | 14 | 0.0 | Default | Axis Label Number |
| `Typography.n10`| DIN Pro | Regular | 10 | 12 | 0.0 | Default | Micro Chart Axis Number |

---

## 2. Color System Tokens (`WhoopDesign.ColorSystem`)

### Canvas & Surfaces

| Token | Hex Value | RGBA Equivalent | Evidence | Usage |
|---|---|---|---|---|
| `canvasGradientTop` | `#273037` | `rgba(39, 48, 55, 1.0)` | `VERIFIED_SCREENSHOT` + `VERIFIED_BINARY` | Top status/header canvas background |
| `canvasGradientBottom`| `#101518` | `rgba(16, 21, 24, 1.0)` | `VERIFIED_SCREENSHOT` + `VERIFIED_BINARY` | Bottom page canvas background |
| `surfacePrimary` | `#1D2429` | `rgba(29, 36, 41, 1.0)` | `VERIFIED_SCREENSHOT` | Standard card background |
| `surfaceElevated`| `#252D33` | `rgba(37, 45, 51, 1.0)` | `VERIFIED_SCREENSHOT` | Elevated card / modal background |
| `surfaceHighlight`| `#2E373E`| `rgba(46, 55, 62, 1.0)` | `VERIFIED_SCREENSHOT` | Pressed card / tile highlight |
| `divider` | `#333E46` | `rgba(51, 62, 70, 0.4)` | `VERIFIED_SCREENSHOT` | Section dividers & card borders |

### Functional Metric Colors

| Metric | Token | Hex Value | Evidence | Usage |
|---|---|---|---|---|
| **Sleep** | `colorSleep` | `#4CA6E6` | `VERIFIED_BINARY` | Primary Sleep Ring & Performance |
| **Sleep Light** | `colorSleepLight` | `#3075A6` | `VERIFIED_BINARY` | Light Sleep Stage |
| **Sleep REM** | `colorSleepREM` | `#A663CC` | `VERIFIED_BINARY` | REM Sleep Stage (Lavender) |
| **Sleep Deep (SWS)** | `colorSleepDeep` | `#1A4366` | `VERIFIED_BINARY` | Slow Wave Sleep Stage (Navy) |
| **Sleep Awake** | `colorSleepAwake` | `#FF6666` | `VERIFIED_BINARY` | Awake periods in hypnogram |
| **Recovery Green** | `colorRecoveryGreen` | `#00E676` | `VERIFIED_BINARY` | Recovery 67–100% |
| **Recovery Yellow** | `colorRecoveryYellow` | `#FFDE00` | `VERIFIED_BINARY` | Recovery 34–66% |
| **Recovery Red** | `colorRecoveryRed` | `#FF3B30` | `VERIFIED_BINARY` | Recovery 1–33% |
| **Strain** | `colorStrain` | `#0091FF` | `VERIFIED_BINARY` | Day Strain Ring & General Strain |
| **Strain Zone 1** | `colorStrainZone1` | `#337099` | `VERIFIED_BINARY` | 50–60% Max HR |
| **Strain Zone 2** | `colorStrainZone2` | `#2D9CDB` | `VERIFIED_BINARY` | 60–70% Max HR |
| **Strain Zone 3** | `colorStrainZone3` | `#00B2FE` | `VERIFIED_BINARY` | 70–80% Max HR |
| **Strain Zone 4** | `colorStrainZone4` | `#F2994A` | `VERIFIED_BINARY` | 80–90% Max HR |
| **Strain Zone 5** | `colorStrainZone5` | `#EB5757` | `VERIFIED_BINARY` | 90–100% Max HR |
| **Stress Low** | `colorStressLow` | `#00E676` | `VERIFIED_BINARY` | Stress 0.0–1.0 |
| **Stress Medium** | `colorStressMedium` | `#FFDE00` | `VERIFIED_BINARY` | Stress 1.0–2.0 |
| **Stress High** | `colorStressHigh` | `#FF3B30` | `VERIFIED_BINARY` | Stress 2.0–3.0 |

---

## 3. Geometry & Layout Tokens

| Token | Dimension (`pt`) | Evidence | Description |
|---|---|---|---|
| `screenPaddingHorizontal` | `16 pt` | `VERIFIED_SCREENSHOT` | Outer card horizontal margins |
| `cardCornerRadius` | `12 pt` | `VERIFIED_SCREENSHOT` | Standard card corner radius |
| `cardInnerPadding` | `16 pt` | `VERIFIED_SCREENSHOT` | Card internal content padding |
| `heroRingOuterDiameter` | `104 pt` | `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT` | Outer circle diameter of score rings |
| `heroRingStrokeWidth` | `8 pt` | `VERIFIED_BINARY` | Ring stroke thickness |
| `heroRingSpacing` | `18 pt` | `VERIFIED_SCREENSHOT` | Gap between adjacent score rings |
| `bottomTabBarHeight` | `56 pt` | `VERIFIED_BINARY` | Tab bar content height (excluding safe area) |
| `tabIconSize` | `24 pt` | `VERIFIED_ASSET` | Bounding box of tab bar icons |
| `tabLabelFontSize` | `10 pt` | `VERIFIED_ASSET` | Proxima Nova Semibold tab text |
| `batteryIconWidth` | `21 pt` | `VERIFIED_SCREENSHOT` | Battery icon width |
| `batteryIconHeight` | `10.5 pt`| `VERIFIED_SCREENSHOT` | Battery icon height (including terminal cap) |
