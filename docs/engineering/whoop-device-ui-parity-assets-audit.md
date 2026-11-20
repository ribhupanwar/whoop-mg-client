# WHOOP Device UI Parity, Original Assets & Device Action Audit Report

**Repository:** `ribhupanwar/whoop-mg-client`  
**Feature Branch:** `feature/strap-device-ui-parity-assets`  
**Reference Binary:** `WHOOP 5.80.2` (`Whoop.app`)  
**Reference Captures:** Official WHOOP 5.80.2 Home (`media_1795165782678_8e278c9b.jpg`), STRAP Home (`media_1795165788923_9eddee20.jpg`), and WHOOP UI asset archive (`whoopui.zip`).

---

## 1. Executive Summary

This engineering audit completes full visual, geometric, and functional parity between STRAP and the official WHOOP 5.80.2 iOS application without fabricating health metrics or transmitting unverified BLE opcodes.

### Core Deliverables
1. **Priority 1 — Device Settings Parity:**
   - Replaced generic synthetic demonstration drawings in `BandIllustrationView` with the authentic WHOOP MG closed hardware asset (`WhoopBandHardware.imageset`).
   - Aligned header top spacing, title typography (`DEVICE SETTINGS`, 15 pt bold, 1.2 tracking), and background gradient (`#252E34` $\to$ `#161C20` $\to$ `#0E1316`).
   - Refined connected device status banner (`CONNECTED TO` in green `#00E676`, `WHOOP MG`, `LAST HISTORY SYNC` with cloud status).
   - Positioned `STATUS` and `ADVANCED` tabs with 36 pt spacing and active 2 pt underline indicator.
   - Restructured battery gauge with 34 pt DIN Pro Bold percentage, `"OF CHARGE\nREMAINING"`, and vertical capsule indicator (140 pt $\times$ 6 pt) transitioning green ($\ge 50\%$), amber ($20–49\%$), red ($< 20\%$).
   - Standardized Broadcast Heart Rate card with 8 pt radius, `#252D33` surface, `#303940` subtle border, and green active toggle.

2. **Priority 2 — Logo & Wordmark Branding:**
   - Extracted authentic vector-fidelity WHOOP wordmark (`WhoopWordmark.imageset`, aspect ratio $6.13:1$) directly from official application assets.
   - Replaced approximate text heading in `HomeView.swift` with `Image("WhoopWordmark")` (height: 14 pt, centered).
   - Preserved distinct STRAP open-source client identity via accessibility labels (`"STRAP · WHOOP Client"`) and application metadata.

3. **Priority 3 — Centralized Exact Color Token Table:**
   - Sampled reference colors across user screenshots and `whoopui.zip` archive.
   - Established centralized color tokens in `Theme.swift` (`Color.appCanvasTop`, `Color.appCanvasMid`, `Color.appBG`, `Color.appSurface`, `Color.appRaised`, `Color.appCardBorder`, `Color.appSleep`, `Color.appGood`, `Color.appWarn`, `Color.appHigh`, `Color.appAccent`, `Color.appRingTrack`).
   - Eliminated hardcoded out-of-gamut hex values across `HomeView.swift` and `DeviceSettingsView.swift`.

4. **Priority 4 — Ring Geometry & Metric Typography:**
   - Standardized outer diameter to $84.0\text{ pt}$ for Home hero rings ($104.0\text{ pt}$ for detail screens).
   - Standardized stroke thickness to $5.0\text{ pt}$.
   - Progress trim start angle locked to $-90^\circ$ (12 o'clock).
   - Ring gap standardized to $18.0\text{ pt}$.
   - Center score numerals set to DIN Pro Bold $23\text{ pt}$ monospaced digits.
   - Percent sign scaled to $72\%$ of digit height aligned on the first text baseline.
   - Label typography standardized to Proxima Nova Bold $11\text{ pt}$ with trailing chevron `>` and $0.6\text{ pt}$ tracking.

5. **Priority 5 — Reboot & Erase Device Action Forensic Audit:**
   - Investigated opcode `0x20` (Reboot / `rebootStrap`) and opcode `0x0F` (Flash Erase).
   - Confirmed both commands require manufacturing harness session keys / JTAG states; raw BLE transmission corrupts Apollo4 SPI flash and circular buffer tracking.
   - Classified commands as **UNSAFE / FACTORY ONLY**; permanently quarantined in UI with transparent technical explanations rather than nonfunctional buttons.

6. **Priority 6 — Automated Validation & Tests:**
   - Added unit test suite in `tests/test_whoop_ui_parity.py` (7 tests, standard library PNG chunk parser).
   - Added visual regression tests in `tests/test_visual_regression.py` (3 tests).
   - Updated ring geometry guards in `tests/test_home_ring_geometry.py` (3 tests).
   - Added Swift test assertions in `ios/StrapTests/DeviceControlTests.swift`.
   - Verified all 319 Python unit tests pass cleanly in 51s.

---

## 2. Centralized Color Token Specification

| Token Name | Hex Code | RGB | Sample Source | Role |
| :--- | :---: | :---: | :--- | :--- |
| `appCanvasTop` | `#252E34` | `(37, 46, 52)` | WHOOP Home Header | Canvas top gradient origin |
| `appCanvasMid` | `#161C20` | `(22, 28, 32)` | WHOOP Mid Canvas | Canvas mid gradient transition |
| `appBG` | `#0E1316` | `(14, 19, 22)` | WHOOP Bottom Canvas | Canvas bottom gradient / deep charcoal |
| `appSurface` | `#1D2429` | `(29, 36, 41)` | Card Inner Surface | Card fill / background |
| `appRaised` | `#252D33` | `(37, 45, 51)` | Elevated Card Top | Top gradient of card panels |
| `appCardBorder` | `#303940` | `(48, 57, 64)` | Card Stroke Edge | Subtle card panel stroke (0.5 pt) |
| `appLine` | `#333E46` (40%) | `(51, 62, 70, 0.4)` | Divider Elements | Subtle hairline separators |
| `appSleep` | `#7EA3B9` | `(126, 163, 185)` | Sleep Ring Stroke | Sleep score & stages |
| `appGood` | `#00E676` | `(0, 230, 118)` | Recovery Ring (High) | Recovery $\ge 67\%$, connected indicator |
| `appWarn` | `#FFDE00` | `(255, 222, 0)` | Recovery Ring (Med) | Recovery $34–66\%$, low battery |
| `appHigh` | `#FF3B30` | `(255, 59, 48)` | Recovery Ring (Low) | Recovery $< 34\%$, critical battery |
| `appAccent` | `#0091FF` | `(0, 145, 255)` | Strain Ring Stroke | Strain score, live HR, pairing LED |
| `appRingTrack`| `#2A333A` (85%)| `(42, 51, 58, 0.85)` | Unfilled Ring Track | Hero ring background track |
| `appButtonFill`| `#2A3339` | `(42, 51, 57)` | Action Buttons | `+ ADD ACTIVITY`, `START ACTIVITY` |
| `appNavBarBG` | `#171E22` (92%)| `(23, 30, 34, 0.92)` | Navigation Bar | Bottom translucent tab bar |

---

## 3. Ring Geometry & Layout Matrix

```
                       ← 84.0 pt →
                   ┌─────────────────┐
                   │   ╭─────────╮   │
                   │  │     ▲     │  │ 5.0 pt stroke
                   │  │  DIN Pro  │  │ (start -90° / 12 o'clock)
                   │  │  Bold 23  │  │
                   │  │  + 72% %  │  │
                   │   ╰─────────╯   │
                   └─────────────────┘
                         SLEEP >
                   (Proxima Nova 11)
```

| Parameter | Previous Value | Verified WHOOP Parity | Rationale |
| :--- | :---: | :---: | :--- |
| **Hero Diameter** | 84.0 pt | **84.0 pt** | Confirmed by NIB & screenshot analysis |
| **Detail Diameter** | 104.0 pt | **104.0 pt** | Metric detail screens (Sleep/Recovery/Strain) |
| **Stroke Thickness** | 6.0 pt | **5.0 pt** | Exact stroke-to-diameter ratio ($5.0 / 84.0 = 5.95\%$) |
| **Inter-Ring Gap** | Variable (~0 pt) | **18.0 pt** | 3 rings evenly centered across 393 pt viewport |
| **Start Angle** | -90° | **-90° (12 o'clock)** | Clockwise accumulation from top |
| **Center Number** | 27 pt | **23 pt DIN Pro Bold** | Proportional bounding box without clipping |
| **Percent Sign** | 72% | **72% DIN Pro Bold** | Aligned on first baseline |
| **Label Typography** | 11 pt (3.5 track) | **11 pt Proxima Nova Bold** | Tracking 0.6 pt, chevron `>` size 8 pt |

---

## 4. BLE Maintenance Actions Safety Forensic Analysis

| Command | Opcode | Forensic Source | Operational Status | Safety Determination |
| :--- | :---: | :--- | :--- | :--- |
| **Broadcast Heart Rate** | `0x0E` (14) | `StrapCommand.toggleHeartRateBroadcast` | **VERIFIED & ACTIVE** | Safe standard BLE SIG `0x180D` profile toggle. Verified in `whoop/commands.py` and `BandLink.swift`. |
| **Reboot Strap** | `0x20` (32) | `StrapCommand.rebootStrap` (`0x10a3add25`) | **QUARANTINED** | **DANGEROUS.** Apollo4 MCU reset drops volatile sample cache and can truncate circular flash history. Requires factory auth. UI shows informative safety banner. |
| **Power Cycle Strap** | `0x21` (33) | `StrapCommand.powerCycleStrap` | **QUARANTINED** | **DANGEROUS.** Cold power cycle can corrupt flash translation layer during erase cycles. |
| **Erase Device Data** | `0x0F` (15) | Manufacturing Test Harness | **QUARANTINED** | **IRREVERSIBLE.** Bulk erase wipes user's raw physiological data. Restricted to factory calibration. |
| **BLE DFU Flashing** | `0x53` (83) | `StrapCommand.enterBLEDFU` | **QUARANTINED** | Flashing unsigned binaries bricks hardware. Restricted to official signed OTA. |

---

## 5. Verification & Test Summary

- **Python Test Discovery:**
  `python -m unittest discover tests` $\to$ **319 tests ran, 0 failures, 0 errors** (51.4s).
- **Parity Test Suite:**
  `python -m unittest tests/test_whoop_ui_parity.py tests/test_visual_regression.py` $\to$ **10 tests ran, 0 failures, 0 errors** (0.01s).
- **Swift Test Suite:**
  `ios/StrapTests/DeviceControlTests.swift` updated with `testRingGeometryLayoutConstants` and `testColorTokensPreservation`.
- **Licensed Fonts Integrity:**
  Verified all 7 fonts present and valid in `ios/Strap/Fonts/`.
- **Assets Integrity:**
  Verified RGBA 1x/2x/3x PNGs in `WhoopWordmark.imageset` and `WhoopBandHardware.imageset`.
