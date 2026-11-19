# Phase 17 — WHOOP Shared UI Components Forensic Audit

**Classification:** `VERIFIED_BINARY` + `VERIFIED_ASSET`  
**Binary Modules:** `WhoopDesign`, `WhoopStyle`

---

## 1. Action Buttons (`WhoopDesign.ActionButton`)

- **Primary Button (`ActionButtonType.primary`):**
  - Height: `52.0 pt` (full-width pill button).
  - Background Color: `#FFFFFF` (Solid White).
  - Text Color: `#101518` (Dark Charcoal).
  - Typography: `ProximaNova-Bold` 16 pt, uppercase, kerning `+0.5 pt`.
  - Corner Radius: `26.0 pt` (fully rounded capsule).

- **Secondary Button (`ActionButtonType.secondary`):**
  - Height: `48.0 pt`.
  - Background Color: `#252D33` (Surface Elevated) or transparent with 1.5 pt white border.
  - Text Color: `#FFFFFF`.
  - Corner Radius: `24.0 pt`.

- **Destructive Button (`ActionButtonType.destructive`):**
  - Background: `#FF3B30` at 15% opacity.
  - Border: 1.0 pt `#FF3B30`.
  - Text: `#FF3B30` `ProximaNova-Bold` 15 pt.

---

## 2. Metric Cards & Tiles (`WhoopDesign.TileColorBackgroundConfig`)

- **Standard Metric Card:**
  - Background: `#1D2429` (Surface Primary).
  - Corner Radius: `12.0 pt`.
  - Padding: `16.0 pt` top, bottom, leading, trailing.
  - Border: `0.5 pt` hairline in `rgba(255, 255, 255, 0.08)`.

- **Small Metric Tile (2-column grid):**
  - Width: `(screenWidth - 44 pt) / 2` (`~165 pt` on standard iPhone).
  - Height: `110.0 pt`.
  - Metric Header: `ProximaNova-Bold` 12 pt, uppercase, `#A3ADB5`.
  - Metric Value: `DINPro-Bold` 24 pt, `#FFFFFF`.
  - Sub-label: `ProximaNova-Regular` 11 pt, `#6D7A84`.

---

## 3. Modals & Bottom Sheets (`WhoopCustomizeBottomSheet`)

- Presentation: Bottom sliding card with grabber handle.
- Background: `#1D2429` with `UIBlurEffect` background dimming.
- Grabber Bar: `36.0 pt x 5.0 pt`, corner radius `2.5 pt`, color `rgba(255, 255, 255, 0.3)`.
- Corner Radius: Top-left `20.0 pt`, top-right `20.0 pt`.

---

## 4. Toggles & Switches (`StateInThumbSwitch` in `WhoopStyle`)

- Custom UISwitch / Toggle:
  - On Tint: `#00E676` (Electric Mint Green).
  - Off Tint: `#3A4650` (Slate Grey).
  - Thumb Color: `#FFFFFF`.
