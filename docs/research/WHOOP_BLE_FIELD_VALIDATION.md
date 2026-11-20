# WHOOP BLE Packet Field Validation & Protocol Forensics

## Overview
This document specifies the decoded packet formats for the WHOOP 4.0 and 5.0 (MG) Bluetooth Low Energy (BLE) protocol, covering real-time telemetry, historical synchronization, ACK handshakes, and diagnostic biometrics.

---

## 1. Real-Time Telemetry: Type-40 Live Packet

- **Service UUID:** `0000FFF0-0000-1000-8000-00805F9B34FB` (Proprietary WHOOP Service)
- **Characteristic:** `0000FFF4-0000-1000-8000-00805F9B34FB` (Notify)
- **Rate:** 1 Hz

| Byte Offset | Field Name | Data Type | Endianness | Scaling / Units | Description | Primary Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `0` | `packet_type` | `uint8` | – | Constant `0x28` (40) | Live heart rate packet identifier | `CAPTURE_VERIFIED` |
| `1` | `heart_rate` | `uint8` | – | Beats per Minute (BPM) | Live real-time heart rate | `CAPTURE_VERIFIED` |
| `2` | `battery_level`| `uint8` | – | Percentage ($0 - 100\%$) | Live battery percentage | `CAPTURE_VERIFIED` |
| `3` | `wear_state` | `uint8` | – | Bit 0: on-wrist ($1$) / off-wrist ($0$) | Optical skin contact indicator | `CAPTURE_VERIFIED` |
| `4–7` | `timestamp` | `uint32` | Little | Seconds since Unix epoch | Device clock timestamp | `CAPTURE_VERIFIED` |

---

## 2. Historical Synchronization: Type-47 / Type-52 Records

- **Historical Command (Request):** Opcode `0x1B` sent to Control Characteristic (`FFF1`).
- **Data Stream:** Packets received on Notification Characteristic (`FFF2`).

### 2.1 Gen 5 Record Header (`BandRecordHeader`)
| Byte Offset | Field Name | Data Type | Endianness | Description | Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `0` | `version` | `uint8` | – | Inner record version (`18` for standard biometrics) | `CAPTURE_VERIFIED` |
| `1` | `flags` | `uint8` | – | Bit 7: PPG rate ($0 = 50\text{ Hz}, 1 = 25\text{ Hz}$) | `CAPTURE_VERIFIED` |
| `2–5` | `record_index` | `uint32` | Little | Monotonic sequential record counter | `CAPTURE_VERIFIED` |
| `6–9` | `unix_sec` | `uint32` | Little | Epoch timestamp in integer seconds | `CAPTURE_VERIFIED` |
| `10–11` | `subsec_q15` | `uint16` | Little | Sub-second fraction ($t = \text{unix} + \frac{Q15}{32768}$) | `CAPTURE_VERIFIED` |

### 2.2 V18 Sensor Payload Layout
| Byte Offset | Field Name | Type | Scaling / Unit | Description |
| :--- | :--- | :--- | :--- | :--- |
| `12` | `heart_rate` | `uint8` | BPM | Filtered PPG heart rate ($35 - 220\text{ BPM}$) |
| `13` | `rr_count` | `uint8` | Count ($0 - 4$) | Number of R-R intervals in current second |
| `14–21` | `rr_intervals` | `uint16[4]` | Little, Milliseconds | Beat-to-beat cardiac intervals |
| `22–23` | `dynamic_accel`| `int16` | $\frac{\text{raw}}{16384}\text{ g}$ | High-pass filtered dynamic movement |
| `24–29` | `gravity_xyz` | `int16[3]` | $\frac{\text{raw}}{16384}\text{ g}$ | Low-pass gravity vector ($X, Y, Z$) |
| `30–31` | `step_counter` | `uint16` | Cumulative count | Hardware pedometer (wraps at 65535) |
| `32` | `step_cadence` | `uint8` | Steps / minute (SPM) | Real-time cadence estimate |
| `33` | `activity_class`| `uint8` | Class ID | $0$: Still, $1$: Walk, $2$: Run |
| `34–35` | `skin_temp` | `int16` | $\frac{\text{raw}}{100} + 25.0\text{ }^\circ\text{C}$ | Contact thermistor measurement |
| `73` | `sleep_state` | `uint8` | Bits 4–5 | $0$: Wake, $1$: Still, $2$: Sleep, $3$: Up |

---

## 3. Handshake, Retransmission & Flow Control

- **ACK Packet:** Opcode `0x1C` containing the highest contiguous `record_index` successfully offloaded and persisted.
- **Backpressure:** Band throttles transmission if ACK packet is delayed by $> 500\text{ ms}$.
- **Reconnection Resumption:** Client queries device head cursor with Opcode `0x1A` and resumes drain from `last_persisted_index + 1`, eliminating duplicate historical records.
