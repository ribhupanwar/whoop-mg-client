# STRAP — WHOOP 5/MG Reboot & Erase Protocol Engineering Audit

**Document Version:** 1.0.0  
**Date:** 2026-11-20  
**Target Repository:** `ribhupanwar/whoop-mg-client`  
**Reference Codebases:**
- `ryanbr/noop` (commit `6948b71`, `StrandTests/FrameRouterRebootAckTests.swift`, `Strand/BLE/Commands.swift`)
- `OpenStrap/edge` (`lib/ble/ble_engine.dart`, `lib/ble/firmware_flash.dart`, `reset_steps_view.dart`)
- `WHOOP 5.80.2` iOS IPA (`Payload/Whoop.app/Whoop`, Ghidra 12.2 disassembler)

---

## 1. Executive Summary & Root Cause Analysis

Previous open-source implementations and early STRAP audits reached the overly conservative conclusion that "rebooting the WHOOP strap over BLE is strictly factory-only and must be permanently quarantined." This investigation demonstrates that this conclusion was based on two compounding protocol errors:

1. **Opcode Confusion (Cold Reset vs Warm Reboot):**
   - Opcode **32 (`0x20`)** (`POWER_CYCLE_STRAP`) is a cold PMIC power-cycle that cuts SoC power rails. Without automated jig hardware, it frequently hangs or ignores packets during live Bluetooth connections.
   - Opcode **29 (`0x1D`)** (`REBOOT_STRAP`) with an empty payload (`[]`) is the official, non-destructive warm MCU reboot recognized and acknowledged by WHOOP 5.0 and WHOOP MG straps running firmware 50.38.1.0 through 50.42.1.0.

2. **The Result Offset Bug (`bhelm/noop#4`):**
   - WHOOP 4.0 uses a 4-byte transport header; its `COMMAND_RESPONSE` (type 36 / `0x24`) result code byte is located at raw packet offset **8**.
   - WHOOP 5.0 and WHOOP MG ("Puffin") use an 8-byte transport header; the inner packet starts at offset 8, and the command result byte is shifted by +4 to raw packet offset **12**.
   - When a client reads offset 8 on a WHOOP 5 frame, it reads the inner packet type byte `0x24` (36). Because 36 is non-zero (whereas `0x01` is SUCCESS and `0x00` is FAILURE), the client falsely concludes that the device rejected the reboot command (`REJECTED`), even though byte 12 was `0x01` (`SUCCESS`)!

| Attribute | Opcode 32 (`0x20`) `POWER_CYCLE_STRAP` | Opcode 29 (`0x1D`) `REBOOT_STRAP` |
| :--- | :--- | :--- |
| **Command ID** | 32 (`0x20`) | 29 (`0x1D`) |
| **Payload Length** | 0 bytes (`[]`) | 0 bytes (`[]`) |
| **Response Type** | Often dropped / No ACK | Puffin `COMMAND_RESPONSE` (`0x24`) |
| **Result Offset** | Byte 8 (4.0) / Byte 12 (5/MG) | Byte 8 (4.0) / Byte 12 (5/MG) |
| **Result Code** | Ignored / N/A | `0x01` (`SUCCESS`) |
| **Flash Data Impact** | High risk of FAT corruption if in flight | **Safe**: Circular NOR flash buffers preserved |
| **Connection Action** | Unclean link drop | Graceful BLE disconnect & restart |
| **Status in STRAP** | **QUARANTINED** | **VERIFIED & ACTIVE** |

---

## 2. Task 1: NOOP Reboot Investigation & Hardware Evidence

Inspection of `C:\Users\ribhu\noop`:
- **File:** `StrandTests/FrameRouterRebootAckTests.swift`:
  - Documents `bhelm/noop#4`:
    ```swift
    // Distinct sentinels at the two candidate result positions.
    var frame = [UInt8](repeating: 0, count: 16)
    frame[8]  = 0x24   // 5/MG inner TYPE byte (COMMAND_RESPONSE)
    frame[12] = 0x01   // 5/MG result = SUCCESS(1)
    XCTAssertEqual(FrameRouter.commandResultByte(in: frame, family: .whoop5), 1)
    ```
- **File:** `Strand/BLE/Commands.swift` line 47:
  - `rebootStrap = 29` (empty body `[]`). Confirmed non-destructive; records stored in SPI NOR flash circular buffers remain intact across restarts.
- **File:** `Packages/WhoopProtocol/Sources/WhoopProtocol/Resources/whoop_protocol.json`:
  - Confirms command catalogue:
    - `FORCE_TRIM = 25` (`0x19`)
    - `REBOOT_STRAP = 29` (`0x1D`)
    - `POWER_CYCLE_STRAP = 32` (`0x20`)
- **File:** `android/app/src/test/java/com/noop/protocol/RebootProbeVariantTest.kt`:
  - Tests candidate commands against physical hardware. Candidate A (opcode 29) consistently succeeds and restarts the radio.

---

## 3. Task 2: OpenStrap Edge Investigation

Inspection of `C:\Users\ribhu\openstrap-edge`:
- **File:** `lib/ble/ble_engine.dart` lines 26 & 5104–5130:
  - Defines `dangerousCmds`:
    ```dart
    static const dangerousCmds = {
      0x19, // FORCE_TRIM (destructive flash erase)
      0x1D, // REBOOT
      0x20, // POWER_CYCLE
    };
    ```
  - OpenStrap blocks these from automated scripts or background threads to prevent unintended disruptions during active streaming.
- **File:** `lib/ble/firmware_flash.dart`:
  - Shows Gen5 firmware staging opcodes (`0x8E`, `0x8F`, `0x90`). Staging requires vendor cryptographically signed image blocks.
- **File:** `lib/ui2/pairing/reset_steps_view.dart`:
  - Implements physical reset instructions (double-tapping strap, sliding battery pack on/off, toggling phone Bluetooth). OpenStrap deliberately avoids issuing on-band destructive memory wipe commands over the air.

---

## 4. Task 3: Disambiguation of Seven Erase & Reset Semantics

To eliminate confusion between distinct operations, STRAP establishes precise operational definitions:

| Operation | Scope | Target | Hardware BLE Opcode | Data Impact | Implementation in STRAP |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Warm Reboot** | Device | MCU / BLE Radio | `0x1D` (29) | None (flash retained) | **Active** (with confirmation dialog) |
| **2. Cold Power Cycle** | Device | PMIC Rails | `0x20` (32) | Risk of flash corruption | **QUARANTINED** |
| **3. Clear App History** | Phone | Local SQLite / Files | None (client-only) | Clears phone UI cache | **Active** ("Clear Local App Cache") |
| **4. Clear Config Flags** | Phone | UserDefaults | None (client-only) | Resets pairing/settings | **Active** ("Unpair Band") |
| **5. Reset Firmware Settings**| Device | Non-volatile NVM | `0x12` / `0x0F` | Erases BLE bonds | **QUARANTINED** |
| **6. Force Trim / Flash Wipe** | Device | SPI NOR Flash | `0x19` (25) | Destroys historical health data | **QUARANTINED** |
| **7. Factory Reset** | Device | Hardware Calibration | Factory Jig Pinout | Resets factory calibration | **QUARANTINED** |

---

## 5. Task 4: Ghidra Reverse Engineering & Binary Ground Truth in WHOOP 5.80.2

Inspection of `Payload/Whoop.app/Whoop`:
- **Symbol:** `sendRebootStrap` at address `0x0000000109a34548`
- **Method:** `DeviceAdvancedSettingsViewModel.rebootStrap` at address `0x000000010a3add25`
- **Constant:** `kBLE_COMMAND_REBOOT_STRAP` at address `0x000000010bfd0936`
- **Constant:** `kBLE_COMMAND_POWER_CYCLE_STRAP` at address `0x000000010bfd1150`
- **Alert Text:**
  - `"Are you sure?"`
  - `"It will take a few minutes to reboot your WHOOP."`
  - Actions: `"Reboot"`, `"Cancel"`

This proves that official WHOOP iOS application uses `sendRebootStrap` (opcode 29) within the Advanced Device Settings view behind an explicit confirmation dialog.

---

## 6. Task 5: STRAP Implementation Details

### A. Python Protocol Module (`whoop/constants.py`)
- Added `Command.REBOOT_STRAP = 0x1D` (29), `Command.POWER_CYCLE_STRAP = 0x20` (32), and `Command.FORCE_TRIM = 0x19` (25).
- Maintained backwards-compatible alias `Command.REBOOT = Command.POWER_CYCLE_STRAP`.
- Defined `DESTRUCTIVE_COMMANDS = frozenset({Command.FORGET_BONDS, Command.POWER_CYCLE_STRAP, Command.FORCE_TRIM})`.
- Added `build_reboot_command(seq: int = 0)`.
- Added `parse_command_response_result(frame: bytes, family: str = "whoop5") -> int | None` with family-aware offset handling (offset 8 for 4.0, offset 12 for 5/MG).
- Added `parse_inner_command_response(inner: bytes) -> dict | None`.

### B. CoreBluetooth State Machine (`ios/Strap/Band/BandLink.swift`)
- Added `@Published private(set) var isRebooting = false`.
- Added `@Published private(set) var rebootMessage: String?`.
- Added `private var rebootExpectedDisconnect = false`.
- Implemented `public func rebootBand()` to enqueue `rebootStrap` (29) with `onWrite` callback setting `rebootExpectedDisconnect = true`.
- Updated `handleFrame` to decode `BandPacket.commandResponse` (`0x24`): validates `inner[2] == 0x1D` and checks `inner[4] == 1` (`SUCCESS`).
- Updated `didDisconnectPeripheral`: intercepts `rebootExpectedDisconnect`, prevents spurious user-facing error banners, and transitions status to `.connecting("Rebooting WHOOP…")` while exponential backoff schedules automatic reconnection.
- Reconnection completion (`status = .connected`) automatically clears `isRebooting` and `rebootMessage`.

### C. Device Settings UI (`DeviceSettingsView.swift` & `HomeView.swift`)
- Replaced quarantined placeholder with active `"REBOOT DEVICE"` button displaying native confirmation dialog:
  - Title: `"Reboot WHOOP?"`
  - Message: `"It will take a few moments to reboot your WHOOP. Historical data stored on your band and phone is preserved."`
  - Actions: `"Reboot"` (role: `.destructive`), `"Cancel"`.
- Added `"CLEAR LOCAL APP CACHE"` button for client-side local cache purge with explicit confirmation.
- Labeled hardware flash wipe `"ON-BAND FLASH ERASE"` as strictly `QUARANTINED` with notice: `"Destructive hardware flash wipe (FORCE_TRIM 0x19) is quarantined. Restricted to factory calibration harnesses."`

---

## 7. Verification & Safety Checklist

- [x] Warm reboot uses verified opcode 29 (`0x1D`) with empty body.
- [x] Command response result byte is extracted family-consciously (offset 12 on WHOOP 5/MG).
- [x] Destructive commands (`FORCE_TRIM` 25, `POWER_CYCLE_STRAP` 32, `FORGET_BONDS` 15) remain strictly quarantined.
- [x] Reboot requires explicit user confirmation via native alert dialog.
- [x] BLE disconnection after reboot is handled cleanly as expected disconnect.
- [x] Exponential backoff reconnects automatically upon strap re-advertisement.
- [x] On-band flash memory circular buffers remain intact across restarts.
- [x] Full Python and Swift unit test suite passes green.
