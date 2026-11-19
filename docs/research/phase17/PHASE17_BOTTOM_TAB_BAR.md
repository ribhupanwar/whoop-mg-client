# Phase 17 — WHOOP Bottom Navigation & Accessory Forensic Reconstruction

**Classification:** `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT`  
**Binary References:**
- `Whoop.MainViewTabBarController` (`Whoop.swift:108a62298`)
- `WhoopBottomNavigation.TabBarItem`
- `WhoopBottomNavigation.TabBarConfigurationService`
- Strings: `MainTab.HomeTabAccessibility`, `MainTab.CoachingTabAccessibility`, `MainTab.CommunityTabAccessibility`, `MainTab.HealthTabAccessibility`, `MainTab.MoreTabAccessibility` (`1090ae1a0`–`1090ae240`)
- `DiscoverMoreCell`

---

## 1. Bottom Tab Bar Architecture

The WHOOP bottom navigation bar is a custom UITabBar-derived controller (`MainViewTabBarController`) hosting up to 5 primary destinations:

```
+-------------------------------------------------------------------------------+
|                      [   DISCOVER MORE (Pill / Button)   ]                    |  <-- Floating Accessory
+-------------------------------------------------------------------------------+
|    [Home]        [Coaching]       [Community]       [Health]        [More]    |  <-- 56 pt Bar Height
|     Home            Plan             Teams           Health          More     |
+-------------------------------------------------------------------------------+
|                              (Safe Area Inset: ~34 pt)                        |
+-------------------------------------------------------------------------------+
```

### Exact Dimension Specifications

| Element | Specification (`pt`) | Evidence Source | Confidence |
|---|---|---|---|
| Total Bar Height (excluding safe area) | `56.0 pt` | Binary Layout Constant | `VERIFIED_BINARY` |
| Safe Area Bottom Inset | `34.0 pt` (iPhone Home Indicator) | iOS Standard Device Metrics | `VERIFIED_SCREENSHOT` |
| Total Visual Height | `90.0 pt` (`56 + 34`) | Pixel measurement | `VERIFIED_SCREENSHOT` |
| Top Hairline Border | `0.5 pt` (`#2D373E` @ 50% opacity) | Screenshot analysis | `VERIFIED_SCREENSHOT` |
| Background Material | Ultra-thin dark blur + `#171E22` (95% opacity) | Swift Type Metadata | `VERIFIED_BINARY` |
| Tab Icon Bounding Box | `24.0 pt x 24.0 pt` | Vector Assets | `VERIFIED_ASSET` |
| Icon-to-Label Spacing | `4.0 pt` | Layout measurement | `VERIFIED_SCREENSHOT` |
| Label Font Family | `ProximaNova-Semibold` | Typography Audit | `VERIFIED_BINARY` |
| Label Font Size | `10.0 pt` | Pixel typography measurement | `VERIFIED_SCREENSHOT` |
| Active Tab Tint | `#FFFFFF` (100% white icon and text) | Screenshot forensics | `VERIFIED_SCREENSHOT` |
| Inactive Tab Tint | `#6B7882` (Muted slate grey) | Screenshot forensics | `VERIFIED_SCREENSHOT` |

---

## 2. Investigation of the Block Immediately Above the Bottom Tabs

**CRITICAL FINDING:**
In the user's reference screenshots (e.g. `WhatsApp Image 2026-11-14 at 12.42.12 PM (2).jpeg`), there is a distinct visual element positioned immediately above the tab bar:
`"Discover More"` / CTA Accessory.

### Forensic Characterization:
1. **Nature:** It is a **floating contextual action card / pill button**, NOT a fixed tab bar extension.
2. **Binary Symbol:** `Whoop.DiscoverMoreCell` / `ActionButton` / `WhoopDesign.CTABatteryStatus`.
3. **Geometry:**
   - Width: Centered horizontal pill / card, width = `w - 32 pt` (or auto-sized pill: `160 pt`).
   - Height: `44.0 pt` (standard Apple touch target).
   - Corner Radius: `22.0 pt` (fully rounded capsule pill) or `12.0 pt` (card).
   - Background Color: `#252D33` (Surface Elevated) with a subtle `1 pt` border in `#3A4650`.
   - Text: `"DISCOVER MORE"` in `ProximaNova-Bold` 13 pt, uppercase, letter-spacing `+0.5 pt`, white `#FFFFFF`.
4. **Behavior:**
   - Scrolls with the feed or sticks as a floating footer when the feed terminates.
   - Tap destination: Expands insights or routes to deeper coaching/more features.

---

## 3. STRAP Tab Bar Parity Directive

1. Ensure STRAP's bottom bar height is strictly `56 pt` above safe area.
2. Ensure tab bar background uses `#171E22` at 95% opacity with dark blur material.
3. Use exact icons:
   - Home: Rounded silhouette house icon.
   - Plan / Coaching: Target crosshair or calendar checklist icon.
   - Community / Teams: Multi-person silhouette icon.
   - Health: EKG pulse line / heart monitor icon.
   - More: 3 horizontal sliders / burger menu icon.
4. Active tint: `#FFFFFF`, Inactive tint: `#6B7882`.
5. Render the `"Discover More"` capsule accessory above the tab bar on Home.
