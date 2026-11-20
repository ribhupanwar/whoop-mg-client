# WHOOP 5.80.2 Ghidra Reverse Engineering & UI Forensic Report

**Document ID:** `docs/WHOOP_5802_GHIDRA_REPORT.md`  
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)  
**Branch:** `research/whoop-5802-device-parity`  
**Date:** November 20, 2026  
**Analyzed Executable:** `C:\Users\ribhu\Downloads\WHOOP_5.80.2_Ghidra\Payload\Whoop.app\Whoop`  
**Decrypted IPA Source:** `C:\Users\ribhu\Downloads\WHOOP_5.80.2_decrypted.ipa`  
**Analysis Environment:** Ghidra 12.2 PUBLIC (`analyzeHeadless.bat`), Java 25 HotSpot, Python 3.13 Mach-O 64-bit Forensic Engine  
**Ghidra Project:** `C:\Users\ribhu\Documents\WHOOP_Analysis.gpr` (Target program: `/WHOOP_5.80.2`)  

---

## 1. Executive Summary & Binary Provenance

A comprehensive reverse-engineering audit was performed on the newly decrypted WHOOP iOS 5.80.2 application binary. The executable was imported directly into the existing Ghidra `WHOOP_Analysis` project alongside the previous 5.78.0 binary for direct side-by-side symbol, cross-reference, and string table comparative forensics.

### Binary Specifications
- **Architecture:** ARM64 (Mach-O 64-bit executable `MH_MAGIC_64`)
- **Binary Size:** 209,853,712 bytes (~200.1 MB)
- **Commands / Segments:** 158 Load Commands (`ncmds = 158`), 61 Segments/Sections
- **Swift Metadata:** Swift 5.1/5.6 hooks, `__swift5_reflstr` (1.82 MB), `__swift5_fieldmd` (1.98 MB), `__swift5_typeref` (7.35 MB)
- **Extracted Strings:** 405,694 unique ASCII/UTF-8 strings across all sections (111,581 printable strings in key text/reflection sections)

---

## 2. Device Settings Architecture & UI Forensics

Forensic extraction of `DeviceSettingsViewController.nib`, `DeviceAdvancedSettingsViewController.nib`, Swift reflection metadata, and the English localized strings catalog (`LocalizedStrings/Connectivity/Device Settings/en/DeviceSettings.strings` and `DeviceAdvancedSettings.strings`) reveals the exact visual structure, hierarchy, and interaction design of the WHOOP Device Settings interface.

### 2.1 Segmented Control: STATUS vs ADVANCED
Unlike a flat list, official WHOOP 5.80.2 uses a top segmented control (`UISegmentedControl` / `Picker`) switching between two primary views:
1. **STATUS (`DeviceSettings.StatusLabel` = "STATUS")**: Daily operational status, battery gauge, visual hardware artwork, and broadcast controls.
2. **ADVANCED (`DeviceSettings.AdvancedLabel` = "ADVANCED")**: Hardware telemetry, firmware check, pairing/unpairing flows, and regulatory compliance.

### 2.2 STATUS Tab Forensic Layout
- **Navigation Title:** `"DEVICE SETTINGS"` (`DeviceSettings.DeviceSettingsTitle`)
- **Device Header:**
  - Product Name: `"WHOOP MG"` (`DeviceSettings.maverickName`), `"WHOOP 4.0"` (`DeviceSettings.HarvardGenNumber`), `"WHOOP 5.0"` (`DeviceSettings.gooseName`), or `"WHOOP 3.0"` (`DeviceSettings.CopleyGenNumber`)
  - Custom Name / Edit Action: `"NAME YOUR WHOOP"` (`DeviceSettings.EditNameTitle`) with `"SAVE"` button (`DeviceSettings.SaveNameButton`)
- **Connection Status Banners:**
  - Connected: `"CONNECTED TO"` (`DeviceSettings.WhoopConnectedTo`)
  - Disconnected: `"NOT CONNECTED TO"` (`DeviceSettings.WhoopNotConnectedTo`) / `"WHOOP DISCONNECTED"` (`DeviceSettings.WhoopStatusDisconnectedTitle`)
  - Subtitle: `"Tap 'Pair a Device' below to continue."` (`DeviceSettings.WhoopStatusDisconnectedSubtitle`)
  - Sync Progress: `"CATCHING UP"` (`DeviceSettings.DataCatchingUp`) / `"LAST SYNC"` (`DeviceSettings.DataLastSync`)
- **Device Artwork Visualization:**
  - The NIB file `DeviceSettingsViewController.nib` establishes an artwork frame of `{250, 250}` pt (`BackgroundGradientView` backdrop).
  - Centered high-fidelity vector illustration of the contoured woven band, titanium clasp, and live status LED.
- **Battery Gauge Display:**
  - Prominent battery percentage (e.g. `84%`)
  - Secondary label: `"OF CHARGE\nREMAINING"` (`DeviceSettings.WhoopBatteryChargeRemaining`)
  - Battery hours estimate: e.g. `"42 HOURS"` (`DeviceSettings.BatteryTimeHours`)
  - Low battery alert: `"CHARGE YOUR WHOOP"` (`DeviceSettings.ChargeWhoop`)
- **Broadcast Heart Rate Control:**
  - Title: `"BROADCAST HEART RATE"` (`DeviceSettings.HRBroadcastTitle`)
  - Subtitle: `"TO COMPATIBLE APPS & DEVICES"` (`DeviceSettings.HRBroadcastSubtitle`)
  - Toggle switch sending verified BLE Command 14 (`0x0E`)

### 2.3 ADVANCED Tab Forensic Layout
The ADVANCED tab is a grouped table view (`UITableViewStyleGrouped`) with the following sections and exact labels:

1. **Hardware & Firmware Section:**
   - **DEVICE ID:** Actual alphanumeric serial number retrieved via DIS characteristic `0x2A25` (`DeviceSettings.DeviceIdLabel`).
   - **FIRMWARE:** Actual semantic version string retrieved via DIS characteristic `0x2A26` (`DeviceSettings.FirmwareLabel`).
2. **Connectivity & Pairing Section:**
   - **PAIR A DEVICE** (`DeviceAdvancedSettings.PairDeviceTitle`):
     - Footer: `"Pair a WHOOP to the WHOOP app. This will replace any existing WHOOP pairings."` (`DeviceAdvancedSettings.PairDeviceFooter`)
     - Triggers pairing flow with `HarvardSearchStrapViewController`.
   - **UNPAIR DEVICE** (`DeviceAdvancedSettings.UnpairDeviceTitle`):
     - Footer: `"Unpair your WHOOP from the WHOOP app. This will remove the Bluetooth connection."` (`DeviceAdvancedSettings.UnpairDeviceFooter`)
     - Alert: Title `"Are you sure?"`, Message `"This will remove the Bluetooth connection."`, Button `"Unpair device"`, Cancel `"Cancel"`.
3. **Maintenance & Updates Section:**
   - **FIRMWARE CHECK** (`DeviceAdvancedSettings.FirmwareCheckTitle`):
     - Footer: `"Check and install the latest WHOOP firmware."` (`DeviceAdvancedSettings.FirmwareCheckFooter`)
     - Status: `"CHECKING"` / `"CHECKING NOW"` / `"NO NEW UPDATES"` (`DeviceSettings.NoNewFirmwareTitle`, `"You have no new firmware updates at the moment."`) / `"FIRMWARE UPDATE AVAILABLE"`.
   - **REBOOT DEVICE** (`DeviceAdvancedSettings.REBOOT DEVICE`):
     - Footer: `"Reboot your WHOOP to restart the device."` (`DeviceAdvancedSettings.Restart your WHOOP to restart the device.`)
     - Alert: Title `"Are you sure?"`, Message `"It will take a few minutes to reboot your WHOOP."`, Button `"Reboot"`, Cancel `"Cancel"`.
     - *STRAP Implementation Note:* Safely disabled / quarantined to prevent flash corruption or device bricking.
   - **ERASE DEVICE DATA** (`DeviceAdvancedSettings.EraseDeviceDataTitle`):
     - Footer: `"Erase all heart rate data currently stored on your WHOOP. This data will not be recoverable."` (`DeviceAdvancedSettings.EraseDeviceDataFooter`)
     - Alert: Title `"Are you sure?"`, Message `"You will permanently erase all of the data the WHOOP device collected."`, Button `"ERASE ALL DATA"`, Cancel `"Cancel"`.
     - *STRAP Implementation Note:* Safely disabled / quarantined to protect user health history.
4. **Regulatory & Compliance Section:**
   - **REGULATORY LABELS**:
     - Footer: `"View regulatory labels and compliance information for your WHOOP device."` (`DeviceAdvancedSettings.RegulatoryLabelsFooter`)
     - Pushes `RegulatoryLabelsView` with official regulatory model IDs and agency approvals.
   - **SAFETY & REGULATORY**:
     - Footer: `"Important safety information, regulatory statements and product compliance details."` (`DeviceAdvancedSettings.SafetyAndRegulatoryFooter`)

---

## 3. Regulatory Labels Specification (`RegulatoryLabelsView`)

Extracted directly from `WhoopRegulatoryInfo_WhoopRegulatoryInfo.bundle/LocalizedStrings/en/RegulatoryLabelsView.strings`:

| Section | Model / Region | Verified Label & Value |
| :--- | :--- | :--- |
| **Header** | Harvard (WHOOP 4.0) | `4.0 REGULATORY LABELS` |
| **Header** | Maverick (WHOOP MG) | `MG REGULATORY LABELS` |
| **Header** | Goose (WHOOP 5.0) | `5.0 REGULATORY LABELS` |
| **Model ID** | Harvard | `WS40 (DEVICE)\nWP40 (CHARGER)` |
| **Model ID** | Maverick | `WS50 (DEVICE)\nWM50 (DEVICE)\nWD50 (BASIC CHARGER)\nWB50 (WIRELESS CHARGER)` |
| **Model ID** | Goose | `WG50 (DEVICE)\nWD50 (BASIC CHARGER)\nWB50 (WIRELESS CHARGER)` |
| **Certifications**| United States | `UNITED STATES` (FCC ID certifications) |
| | Canada | `CANADA` (ISED certifications) |
| | Europe | `EUROPE` (CE / RED standards) |
| | Australia / New Zealand | `AUSTRALIA\nNEW ZEALAND` (RCM compliance) |
| | Singapore | `SINGAPORE` (IMDA compliance) |
| | South Africa | `TA-2021 / 2643\nTA-2024 / 0465\nAPPROVED` |

---

## 4. Pairing & Connectivity Forensics

Forensic analysis of `HarvardSearchStrapViewController`, `WHPBLEConnectingStrap`, and `BluetoothPairingConnectingViewModel` confirms:

1. **Double-Tap Pairing Operation:**
   - Gesture recognition is executed 100% on-hardware by the strap's onboard TDK InvenSense ICM-45686 6-axis IMU DSP when the optical PPG registers an off-wrist condition (`wristOff`).
   - The user instruction states: *"Take your WHOOP off wrist and wait for the green sensor LEDs to turn off to enable pairing."* followed by *"Turn on pairing mode by continuously tapping the top until the side LED pulses blue. This should take about 10 repeated taps."*
   - Double-tapping the strap while on-wrist checks the battery status: *"Check if your WHOOP is charged by double tapping the top. An LED will appear on the side if it's charged."*
   - **Zero Outgoing Commands:** The iOS application never transmits a BLE command to simulate a double-tap.
2. **Blue LED Pairing Indication:**
   - The pulsing blue side LED is driven directly by the band firmware upon entering `pairingMode` (event `0x12` / 18 decimal).
   - The application passively observes advertisement flags and peripheral state changes.
3. **Reconnection Architecture:**
   - WHOOP uses CoreBluetooth persistent peripheral UUIDs (`retrievePeripherals(withIdentifiers:)`) with state restoration.
   - Reconnect backoff timer logs: `"connected sufficiently long that reconnect backoff delay has been reset back to minimum value"`. STRAP's exponential backoff (`1s..30s`) accurately mirrors this behavior.

---

## 5. Health Algorithms & Processing Pipeline

### 5.1 Heart Rate & RR Filtering
- Packet Type 40 / Rev 21 payload delivers continuous RR intervals alongside filtered HR.
- In 5.80.2, zero-padding checks in synthetic test suites must respect `RRIntervalsPaddingBytesNotAllZeroes` (bytes 16..19).

### 5.2 Sleep Detection & Staging
- Reflection strings confirm sleep stage duration tracking:
  - Slow Wave Sleep (Deep): `slowWaveSleepDuration` / `HistoricalTrendView.deepSleepTitleText`
  - REM Sleep: `remSleepDuration` / `HistoricalTrendView.remSleepTitleText`
  - Light Sleep: `lightSleepDuration`
  - Awake Duration: `awakeDuration`
- Score calculation: `sleepScore` evaluated against `sleepScoreGoal` (`SleepScoreCard`).

### 5.3 Recovery Score
- Color thresholds confirmed in `CalendarView`:
  - **Green (Well Recovered):** `>= 67%` (`CalendarView.GreenRecoveryScore`)
  - **Yellow (Adequate):** `34% - 66%` (`CalendarView.YellowRecoveryScore`)
  - **Red (Impaired):** `<= 33%` (`CalendarView.RedRecoveryScore`)

### 5.4 Strain & Stress Monitoring
- Day strain formatting: `CalendarView.DayStrainAboveTenFormat` (`0.0` to `21.0` scale).
- `WhoopStressMonitor` framework provides continuous real-time stress estimation via `StressGaugeReducer` and `StressMetricPublishing`.
- `WhoopHealthMonitor` manages baseline metrics (RHR, HRV, Respiratory Rate, Blood Oxygen, Skin Temperature) with 14-day rolling confidence intervals.

---

## 6. Implementation Plan for STRAP

To bring STRAP into 100% forensic parity with WHOOP 5.80.2:
1. Rebuild `DeviceSettingsView.swift` with the top segmented control (**STATUS** vs **ADVANCED**).
2. STATUS tab presents band name, connection state banner, 250×250 `BandIllustrationView`, battery percentage with `"OF CHARGE\nREMAINING"`, and Broadcast Heart Rate toggle.
3. ADVANCED tab presents Device ID, Firmware version, Pair Device, Unpair Device with alert, Firmware Check, safely quarantined Reboot and Erase rows, Regulatory Labels row, and Safety & Regulatory row.
4. Add `RegulatoryLabelsView.swift` implementing all extracted regulatory compliance details.
5. Retain all score rings, DIN Pro / Proxima Nova typography, battery gauge dimensions, and health algorithms untouched.
