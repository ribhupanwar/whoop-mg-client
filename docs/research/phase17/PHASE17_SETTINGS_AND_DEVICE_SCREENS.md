# Phase 17 — WHOOP Device & Settings Screens Forensic Audit

**Classification:** `VERIFIED_ASSET` + `VERIFIED_BINARY`  
**Binary Modules:** `WhoopHRSettings`, `WhoopActivityDetectionSettings`, `WhoopPairingFeature`  
**Bundle Origin:** `WhoopMenu_WhoopMenu.bundle/LocalizedStrings/en/DeviceSettings.strings`

---

## 1. Device Settings Screen (`DeviceSettingsView`)

```
+-------------------------------------------------------------+
| < SETTINGS                  DEVICE SETTINGS                 |
+-------------------------------------------------------------+
|                                                             |
|   +-----------------------------------------------------+   |
|   |                  [ WHOOP BAND GRAPHIC ]             |   |
|   |               CONNECTED TO WHOOP MG                 |   |
|   |         Battery: 85%  |  Last Sync: 12:26 PM        |   |
|   +-----------------------------------------------------+   |
|                                                             |
|   HARDWARE DETAILS                                          |
|   Device Name:                      WHOOP MG (Maverick)     |
|   Serial Number:                    WP40-XXXX-XXXX          |
|   Bluetooth Signal (RSSI):          -58 dBm (Strong)        |
|                                                             |
|   PREFERENCES                                               |
|   Broadcast Heart Rate:             [ ON / OFF Toggle ]     |
|   Device Location:                  Left Wrist >            |
|                                                             |
|   FIRMWARE                                                  |
|   Firmware Version:                 41.14.3.0               |
|   Status:                           UP TO DATE              |
|   [ CHECK FOR UPDATES ]                                     |
|                                                             |
|   ADVANCED ACTIONS                                          |
|   Reboot Device                                             |
|   Power Cycle                                               |
|   Recalibrate Optical Sensor                                |
|   Unpair Device                                             |
+-------------------------------------------------------------+
```

---

## 2. Activity Detection Settings (`WhoopActivityDetectionSettings`)

- Auto-detection sensitivity slider: Low, Medium, High.
- Minimum activity duration threshold: 15 minutes.
- Auto-log vs manual confirmation toggle.

---

## 3. Data Export & Backup Screen (`WhoopDataExport`)

- Export formats supported:
  - CSV Health Summary
  - JSON Metrics Archive
  - GPX GPS Track Export
  - FIT Workout Export
- STRAP parity matches existing backup implementation in `StrapBackup.swift`.
