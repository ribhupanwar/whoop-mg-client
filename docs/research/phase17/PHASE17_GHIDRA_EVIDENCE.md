# Phase 17 — Ghidra Forensic Evidence & Cross-References

**Binary Analyzed:** `Whoop` (Mach-O 64-bit arm64, 202,700,624 bytes)  
**Ghidra Project:** `C:\Users\ribhu\Documents\WHOOP_Analysis.gpr`  
**Extractor Script:** `WhoopUIForensicExtractor.java` (executed via headless analyzer)  
**Output Records:** 1,795 UI symbols, 1,675 UI strings extracted.

---

## 1. Key Binary Symbols & Addresses

| Symbol / Class Name | Binary Address | Type | Function / Description |
|---|---|---|---|
| `_TtC5Whoop24MainViewTabBarController` | `0x108a62298` | Swift Class | Central root tab navigation coordinator |
| `_TtC5Whoop30StrapSettingsBatteryStatusView`| `0x108a33518` | Swift Class | Hardware battery indicator & status popover |
| `WHPBatteryView` | `0x108a577d0` | ObjC Class | Top navigation bar battery icon view |
| `_TtC22WhoopDesignTestHelpers17ScoreGaugeFixture`| `0x10ad8a068` | Swift Class | Score gauge calibration & layout test fixture |
| `_TtC19WhoopDesignShowcase23TypographyShowcaseStore`| `0x10ad896c8` | Swift Class | System-wide typography catalog store |
| `applyLocalizedProximaNovaFonts` | `0x1093b2f9f` | Method Selector| Dynamic font family applicator |
| `dinProWithWeight:size:` | `0x1093cbaa6` | Method Selector| Numeric font constructor |

---

## 2. Navigation Strings & Accessibility Tokens

| Address | Extracted String Token | UI Significance |
|---|---|---|
| `0x1090ae240` | `MainTab.HomeTabAccessibility` | Home / Overview Tab Accessibility Identifier |
| `0x1090ae210` | `MainTab.CoachingTabAccessibility` | Coaching / Plan Tab Accessibility Identifier |
| `0x1090ae1c0` | `MainTab.CommunityTabAccessibility`| Community / Teams Tab Accessibility Identifier |
| `0x1090ae1f0` | `MainTab.HealthTabAccessibility` | Health Monitor Tab Accessibility Identifier |
| `0x1090ae1a0` | `MainTab.MoreTabAccessibility` | More / Settings Tab Accessibility Identifier |
| `0x10909aeb6` | `BatteryIcon` | Top-right battery asset key |
| `0x10909aec2` | `BatteryChargingIcon` | Battery charging state asset key |
| `0x10909bb80` | `WHPWhoopStrapBatteryStatusChanged` | NSNotificationCenter battery broadcast key |

---

## 3. Font Name Table in Binary (`__TEXT.__cstring`)

| Address | Font PostScript Name | Target Weights |
|---|---|---|
| `0x10915191a` | `ProximaNova` | Base family name |
| `0x1091a1b10` | `ProximaNova-Regular` | 400 Regular |
| `0x1091a1f30` | `ProximaNova-Medium` | 500 Medium |
| `0x1091a1af0` | `ProximaNova-Semibold` | 600 Semibold |
| `0x10909c1f0` | `ProximaNova-Bold` | 700 Bold |
| `0x1091a1f50` | `ProximaNova-Black` | 900 Black |
| `0x109151926` | `DINPro` | Base numeric family name |
| `0x1091a1c34` | `DINPro-Regular` | 400 Regular |
| `0x1091a1c43` | `DINPro-Medium` | 500 Medium |
| `0x1091a1c51` | `DINPro-Bold` | 700 Bold |
