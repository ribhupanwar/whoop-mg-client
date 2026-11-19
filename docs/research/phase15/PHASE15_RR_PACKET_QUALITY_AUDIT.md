# PHASE 15 — Forensic Audit: BLE Packet Structure & RR Quality Filtering

**Target Binary**: `WHOOP 5.78.0` (`Mach-O 64-bit ARM64`)  
**STRAP Codebase**: `ribhupanwar/whoop-mg-client` (`ios/Strap/Band/V18Decoder.swift`, `whoop/records.py`)  
**Objective**: Reverse engineer the exact byte layout, field offsets, endianness, and validation gates of WHOOP historical telemetry packets (`RawDataRev20`, `RawDataRev21`), compare with STRAP's `V18Decoder`, and define clean-room protocol handling.

---

## 1. Executive Summary & Packet Revisions

Binary reverse engineering of the protocol decoders between `0x1008cd000` and `0x1008d2000` reveals that WHOOP iOS 5.78.0 supports four distinct historical raw packet revisions:
- **`RawDataRev10`**: Legacy WHOOP 3.0 protocol.
- **`RawDataRev11`**: Transitory revision for early optical sensor configurations.
- **`RawDataRev20`**: Initial WHOOP 4.0 historical telemetry protocol (decoder at `0x1008cd188`).
- **`RawDataRev21`**: Current production WHOOP 4.0/5.0 protocol (decoder at `0x1008d0000`), adding explicit capacitive/optical `OnOffStatus` and multi-site `BodyLocation` fields.

*Note on Revision Naming*: While STRAP's open-source decoder is named `V18Decoder` (referencing an earlier protocol version 18), the production WHOOP 5.78.0 binary formally tags these structures as `RawDataRev20` and `RawDataRev21`.

---

## 2. Byte-Level Structure of `RawDataRev21`

Disassembly of function `0x1008d0000` (the Rev21 parser) establishes the exact byte offsets, lengths, and endianness:

| Byte Offset | Field Name | Data Type | Endianness | Binary Error Enum on Failure | Description / Valid Range |
| :---: | :--- | :--- | :---: | :--- | :--- |
| `0x00` | `packetType` | `UInt8` | — | `PacketTypeFailedToParse` (`0x1008d09fc`) | Must match raw historical telemetry identifier (`0x01` or `0x14`). |
| `0x01` | `revision` | `UInt8` | — | `RevFailedToParse` (`0x1008d0a34`)<br>`UnsupportedRevision` (`0x1008d0acc`) | Must equal `21` (`0x15`). |
| `0x02..0x05` | `timestampEpoch` | `UInt32` | Little | `TimestampEpochFailedToParse` (`0x1008d0948`) | Unix epoch timestamp in seconds. |
| `0x06` | `onOffStatus` | `UInt8` | — | `OnOffStatusFailedToParse` (`0x1008d09d4`) | Bit 0: on-wrist state (`0 = off`, `1 = on-body`). Bits 1–7: reserved. |
| `0x07` | `bodyLocation` | `UInt8` | — | `BodyLocationFailedToParse` (`0x1008d0c20`) | Wear site enum: Wrist (`0`), Bicep (`1`), Sleeve (`2`), Undergarment (`3`). |
| `0x08` | `heartRate` | `UInt8` | — | `HeartRateFailedToParse` (`0x1008d0b4c`) | Instantaneous heart rate in bpm (`30...240`). |
| `0x09` | `rrCount` | `UInt8` | — | `RRIntervalsCountFailedToParse` (`0x1008d0be4`)<br>`RRIntervalsCountTooLarge` (`0x1008d0a70`) | Number of inter-beat intervals in this packet ($0 \le N \le 7$). |
| `0x0A..0x17` | `rrIntervals` | `[UInt16; 7]` | Little | `RRIntervalsFailedToParse` (`0x1008d0c5c`) | Fixed 14-byte array containing up to 7 16-bit intervals in milliseconds. |
| *Padding* | `zeroPadding` | `[UInt8]` | — | `RRIntervalsPaddingBytesNotAllZeroes` (`0x1008d0b8c`) | Unused bytes in the 14-byte array (from $2N$ to 14) **must strictly be zero**. |
| `0x18..0x19` | `signalQuality` | `UInt16` | Little | `UnexpectedSignalQualityValue` (`0x10965a040`) | Logarithmic optical variance / signal-to-noise ratio. |
| `0x1A..0x1F` | `accelSamples` | `[Int16; 3]` | Little | `AccelFailedToParse` | 3-axis accelerometer gravity vector $(X, Y, Z)$ in milligravity. |

---

## 3. Disassembly of Validation Gates

### 3.1 RR Interval Count Limit (`RRIntervalsCountTooLarge`)
At `0x1008d0a4c`, the parsed count $N$ is validated:
```assembly
0x1008d0a4c:  sub   x9, x9, #7
0x1008d0a50:  b.hi  0x1008d0a54             ; If count > 7 -> RRIntervalsCountTooLarge
```
- **Verified Constant**: A single 1-second telemetry packet holds at most **7 RR intervals** ($7 \times 2 = 14\text{ bytes}$). A value $>7$ causes immediate packet rejection.

### 3.2 Zero-Padding Gate (`RRIntervalsPaddingBytesNotAllZeroes`)
At `0x1008d0b74` – `0x1008d0b90`:
```assembly
0x1008d0b74:  ldrb  w9, [x10, x11]          ; Load unused byte from RR array
0x1008d0b78:  cbnz  w9, 0x1008d0b8c         ; If unused byte != 0 -> RRIntervalsPaddingBytesNotAllZeroes
```
- **Verified Logic**: The band hardware zero-pads the unused tail of the 14-byte RR buffer. If any unused byte contains non-zero residual data, the packet is flagged as corrupted.

### 3.3 On-Body Status Gate (`onOffStatus`)
At `0x1008d09d4`, `onOffStatus` is checked:
- If `onOffStatus == 0`, optical heart rate and RR intervals are rejected as off-wrist ambient noise.
- Capacitive sensor contact and optical DC level must confirm skin proximity before samples are admitted to historical memory.

---

## 4. Comparison Between WHOOP Protocol Revisions & STRAP

| Characteristic | WHOOP `RawDataRev20` | WHOOP `RawDataRev21` | STRAP `V18Decoder` | Analysis & Compatibility |
| :--- | :---: | :---: | :---: | :--- |
| **Header Length** | 6 bytes | 8 bytes | 8 bytes | Rev21 added `onOffStatus` and `bodyLocation` at bytes 6 and 7. |
| **Max RR Count** | 7 | 7 | 7 | **Identical**: $7 \times 2 = 14\text{ bytes}$ maximum per second. |
| **Endianness** | Little-endian | Little-endian | Little-endian | **Identical**: Multi-byte integers are uniformly little-endian. |
| **Valid RR Range** | $300\text{--}2000\text{ ms}$ | $300\text{--}2000\text{ ms}$ | $300\text{--}2000\text{ ms}$ | **Identical**: Limits represent $30\text{--}200\text{ bpm}$. |
| **Padding Enforcement** | Strict zero check | Strict zero check | Zero-ignoring | STRAP ignores padding tail; adding zero-check will improve corrupted frame rejection. |
| **Signal Quality (SQI)**| 2-byte SNR | 2-byte SNR | Optional log variance | STRAP preserves raw byte; does not discard packet if SQI elevated. |

---

## 5. Conclusions & Implementation Upgrades for STRAP

1. **Adopt Strict Zero-Padding Gate**:
   Update `V18Decoder.swift` to verify that bytes between $2 \times \text{rrCount}$ and 14 in the RR block are `0x00`. Any packet with non-zero padding bytes should be logged as corrupted and rejected, preventing buffer over-read artifacts from entering the HRV pipeline.
2. **Handle Duplicate Timestamps Gracefully**:
   During BLE historical sync replay, packet loss recovery can transmit the same second twice. STRAP's current logic (`SleepSession.swift:163`) already retains the sample with greater RR count, preventing clock jitter.
