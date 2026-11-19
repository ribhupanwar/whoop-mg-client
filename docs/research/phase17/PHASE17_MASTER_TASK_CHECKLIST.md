# Phase 17 — Master Forensic Execution & Implementation Checklist

**Execution Status:** In Progress  
**Authoritative Baseline:** Production `main` at `ebf13f7`

---

## 1. Forensic Extraction Deliverables (All Completed)

- [x] **Locate Tools & Resources:**
  - Located `analyzeHeadless.bat` at `C:\Users\ribhu\Downloads\ghidra_12.2_PUBLIC\support\analyzeHeadless.bat`.
  - Located Ghidra project at `C:\Users\ribhu\Documents\WHOOP_Analysis.gpr`.
  - Located analyzed binary at `C:\Users\ribhu\whoop-ipa-analysis\Payload\Whoop.app\Whoop`.
- [x] **Autonomous Ghidra Extraction:**
  - Executed `WhoopUIForensicExtractor.java` in headless mode without disturbing GUI lock.
  - Extracted 1,795 UI symbols to `ghidra_ui_symbols.json`.
  - Extracted 1,675 UI strings to `ghidra_ui_strings.json`.
  - Extracted navigation cross-references to `ghidra_navigation_xrefs.json`.
- [x] **Bundle & Asset Extraction:**
  - Decoded 133 bundles across `Payload/Whoop.app`.
  - Extracted full English navigation tree from `WhoopMenu_WhoopMenu.bundle`.
  - Extracted device settings taxonomy from `DeviceSettings.strings`.
- [x] **Screenshot Forensic Measurement:**
  - Built Windows OCR pipeline using `winrt-Windows.Media.Ocr`.
  - Indexed all 67 reference screenshots across `UI`, `HEALTH`, `RECOVERY`, `SLEEP`, `STRAIN`, `STRAP`.
  - Measured exact sub-pixel dimensions for battery icon (21x10.5 pt), rings (104 pt outer, 8 pt stroke, 18 pt gap), and tab bar (56 pt height).
- [x] **Required Phase 17 Research Artifacts:**
  - [x] `PHASE17_COMPLETE_SCREEN_INVENTORY.md`
  - [x] `PHASE17_DESIGN_TOKENS.md`
  - [x] `PHASE17_TYPOGRAPHY_AUDIT.md`
  - [x] `PHASE17_COLOR_PALETTE.md`
  - [x] `PHASE17_ICON_INVENTORY.md`
  - [x] `PHASE17_BATTERY_UI_FORENSICS.md`
  - [x] `PHASE17_HOME_GEOMETRY.md`
  - [x] `PHASE17_RING_GEOMETRY.md`
  - [x] `PHASE17_BOTTOM_TAB_BAR.md`
  - [x] `PHASE17_MORE_MENU_COMPLETE_TREE.md`
  - [x] `PHASE17_HEALTH_SCREENS.md`
  - [x] `PHASE17_SLEEP_SCREENS.md`
  - [x] `PHASE17_RECOVERY_STRAIN_SCREENS.md`
  - [x] `PHASE17_ACTIVITY_SCREENS.md`
  - [x] `PHASE17_COMMUNITY_SCREENS.md`
  - [x] `PHASE17_SETTINGS_AND_DEVICE_SCREENS.md`
  - [x] `PHASE17_SHARED_COMPONENTS.md`
  - [x] `PHASE17_GHIDRA_EVIDENCE.md`
  - [x] `PHASE17_ASSET_CATALOG_AUDIT.md`
  - [x] `PHASE17_SCREENSHOT_DIFF_REPORT.md`
  - [x] `PHASE17_STRAP_IMPLEMENTATION_MATRIX.md`
  - [x] `PHASE17_MASTER_TASK_CHECKLIST.md`

---

## 2. Implementation Execution Backlog (Strict Priority Order)

### Batch P0 — Critical Structural Anchors
- [ ] **P0.1 Design Tokens:** Add centralized `WhoopDesign.Typography` tokens and exact `ColorSystem` hex constants to `ios/Strap/Theme.swift`.
- [ ] **P0.2 Battery Icon:** Implement custom vector battery shape in `ios/Strap/Components.swift` (21 pt x 10.5 pt, 2.5 pt corner radius, terminal cap, dynamic fill, trailing DIN Pro percentage).
- [ ] **P0.3 Score Rings Numerics:** Switch center score numbers to `DINPro-Medium` 24 pt and `%` to `DINPro-Regular` 14 pt in `RingView`.
- [ ] **P0.4 Bottom Tab Bar:** Set height strictly to `56 pt` above safe area, apply `#171E22` material with 0.5 pt top border, and calibrate active (`#FFFFFF`) / inactive (`#6B7882`) tints.
- [ ] **P0.5 Floating Above-Tab Accessory:** Add centered `"DISCOVER MORE"` pill button (`160x44 pt`, `#252D33`, 22 pt corner radius) immediately above the bottom tabs.
- [ ] **P0.6 More Menu Hierarchy:** Reorganize `MoreView.swift` into the verified 3-section structure (`SHOP & GIFT`, `ACCOUNT & SETTINGS`, `SUPPORT`).

### Batch P1 — Core Home Cards & Detail Screens
- [ ] **P1.1 Home Canvas Background:** Adjust vertical gradient to top `#273037` and bottom `#101518`.
- [ ] **P1.2 Health Monitor Card:** Expand to 5-biomarker matrix (Respiratory Rate, SpO2, Resting Heart Rate, HRV, Skin Temperature) with colored baseline status dots.
- [ ] **P1.3 Stress Monitor Tile:** Implement 24-hour scrolling stress graph with 3 colored zones (Green, Yellow, Red).
- [ ] **P1.4 Sleep Stages Hypnogram:** Update hypnogram colors to exact WHOOP hex values (Awake `#FF6666`, Light `#3075A6`, REM `#A663CC`, Deep `#1A4366`).
- [ ] **P1.5 Strain Coach Corridor:** Add dynamic optimal strain target corridor based on morning recovery.

### Batch P2 & P3 — Secondary Screens & Final Polish
- [ ] **P2.1 Activity Feed Cards:** Sport-specific vector icons in 36 pt `#0091FF` badge with trailing strain score pill.
- [ ] **P2.2 Device Settings Screen:** Connected WHOOP MG hardware graphic, firmware check status, and optical recalibration / reboot controls.
- [ ] **P3.1 Animation & Transitions:** Smooth tab transitions, pulse animations on live HR marker.
- [ ] **P3.2 Regression Verification:** Execute native iOS build, unit tests, and side-by-side screenshot overlay comparisons.
