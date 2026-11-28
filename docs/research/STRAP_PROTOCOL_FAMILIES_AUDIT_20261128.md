# STRAP — Five-Family Sensor Protocol Audit (Rev10, V18, V20, V21, V26)

**Date:** 2026-11-28  
**Baseline:** `main` @ `3dea671` (coordinated with PR #327 merged and PR #331 open)  
**Scope:** Field-by-field Swift vs Python protocol audit across Rev10, V18, V20, V21, and V26; real capture validation; surgical parity fixes only. Frozen sleep, HRV, RHR, recovery, and step algorithms (`docs/algorithm-freeze.json`) untouched.

---

## 1. Real Capture Fixture Validation (`research-inputs/`)

Executed `research-inputs/scan_captures.py` and `research-inputs/validate_real_captures.py`:
- **Total capture files:** `497` (`575,551` reassembled frames)
- **Packet type distribution:** `0x2F` (`503,469`), `0x32` (`30,771`), `0x31` (`18,866`), `0x24` (`11,257`), `0x30` (`6,646`), `0x28` (`4,009`), `0x36` (`533`)
- **Historical (`0x2F`) version distribution:**
  - `Version 18`: `487,040` frames (`112` bytes inner)
  - `Version 26`: `16,429` frames (`76` bytes inner)
  - `Rev10` / `V20` / `V21` / `V22`: `0` frames in current physical captures
- **V18 physical field ranges (`487,040` frames):**
  - HR: `50..150` bpm (`486,859` valid)
  - RR: `333..2400` ms (`387,804` valid beats; `0/487,040` nonzero unused padding bytes)
  - Skin temp: `26.04..39.76 °C` (mean `33.01 °C`); Aux1 `22.9..39.3 °C`; Aux2 `24.7..39.0 °C`
  - Dynamic accel: `0.0031..12.8040 g`; Activity classes: `{0, 1, 2}`
  - SpO₂ candidate: `2..168` (`42` distinct values)
  - pSNR B/A: `-128..70` / `-128..76` (`152,003` unavailable `-128` frames); Log variance: `-5.287..0.000`

---

## 2. Exact-File-and-Line Findings Matrix

| Family | File & Lines (Swift / Python) | Audit Finding | Classification | Action |
|---|---|---|---|---|
| **Rev10** | `ios/Strap/Protocol/Gen5IMUBuffer.swift:301-325`; `ios/Strap/Band/BandLink.swift:2890-2892` | Ghidra 5.78 `RawDataRev10` strings (`0x109658e90-0x109659690`) and packet-relative offsets (`0x0F` subsec, `0x15` HR, `0x59/0x121/0x1E9` accel, `0x2B4/0x37C/0x444` gyro, `200`-byte = `100 × Int16` axis arrays) sit `+4` bytes above `Gen5R10RawCandidate` inner-relative offsets (`11` subsec, `17` HR, `85/285/485` accel, `688/888/1088` gyro, `bytes.count == 1932`, `0x28`/`0x2B`, `bytes[1] == 10`). Passively stored only; `0` real Rev10 frames in captures. | **RESEARCH GAP** / **ALREADY IMPLEMENTED** (passive guard) | Keep passive-only; require physical Rev10 capture before production use. |
| **V18** | `ios/Strap/Protocol/V18Record.swift:225-358`; `whoop/records.py:234-317` | Exact field-by-field parity across HR (`25..230`), RR (`declared <= 4`, `200..3000`, `rrPaddingValid`), accel (`0..16 g`), gravity (`±16 g`), step counter (`u16@49`), cadence (`u8@51`), activityClass (`u8@55`), cardiacFlags (`@25`), hrQualityFlags (`@28`), temps (`@61/10`, `@63/10`, `@65/100`, rejecting `-32768/32767/0` and `-20..80 °C` incl. `-5000`), sleepState (`@73` bits 4-5), SpO₂ candidate (`@74`), pSNR (`@100/@101`), logVar (`f32@105`). | **ALREADY IMPLEMENTED** | Verified on `487,040` real V18 frames; no code change needed. |
| **V20** | `ios/Strap/Protocol/Gen5V20Record.swift:44-96`; `whoop/records.py:526-555`; `BandLink.swift:3000` | Exact parity: `2128` B inner, `0x2F`, `v=20`, `5` blocks × `422` B, `count <= 50`, `sampleRateHz = u16(15) (0->nil)`, signed 20-bit `-524288..524287`, saturation & flatline counters. Routed to `pendingNativeDeepTelemetry`. | **ALREADY IMPLEMENTED** / **RESEARCH GAP** (0 physical V20 frames) | No defect; keep diagnostics-only until physical V20 capture. |
| **V21** | `ios/Strap/Protocol/Gen5IMUBuffer.swift:53-139`; `whoop/records.py:432-483` | `whoop/records.py:452` accepted any `inner[0]` byte for `1232`-byte buffers, whereas Swift `Gen5IMUBuffer.swift:56` requires `0x2F` or `0x2B` (rejecting `0x34`). `IMURhythmWindow` (`Gen5IMUBuffer.swift:86-139`) checks `version == 21`, wrap `&+ 1`, gaps, and replay. | **VERIFIED DEFECT** (Python packet-type check) | Added `inner[0] not in (0x2F, 0x2B)` guard in `whoop/records.py:452`, `test_unverified_packet_type_rejected` in `tests/test_records.py`, and `IMURhythmWindow` wrong-version/wrap/replay test in `Gen5IMUBufferTests.swift`. |
| **V26** | `ios/Strap/Protocol/Gen5V26Record.swift:46-85`; `whoop/records.py:356-399` | Swift `Gen5V26Record.swift:78` read `firstSampleADC` as `Int32(bitPattern: u32(15))` without 20-bit two's-complement sign extension (`0x00080000..<0x00100000`), whereas Python `whoop/records.py:375-377` sign-extended 20-bit anchors (`1 << 19`..`1 << 20`). Python `decode_v26` (`whoop/records.py:396`) intentionally preserves full `float32` accel precision (`places=6` tested). | **VERIFIED DEFECT** (Swift 20-bit anchor sign-ext) | Fixed 20-bit anchor sign extension in `Gen5V26Record.swift:76-82` and added `testTwentyBitNegativeAnchorSignExtendsToParityWithPython` in `Gen5V26Tests.swift`. |

---

## 3. Outstanding Hardware Validation Gaps

1. **Rev10 (`RawDataRev10` / `Gen5R10RawCandidate`)**: Zero physical Rev10 frames in `research-inputs/`; requires real band capture to pin `+4` vs `+8` header shift, scale factors, and timestamps.
2. **V20 / V21 (`Gen5V20Record` / `Gen5IMUBuffer`)**: Zero physical V20/V21 frames in `research-inputs/`; requires real band capture to confirm 100 Hz IMU scaling (`1/4096 g`, `2000/32768 dps`) and optical block continuity.
3. **V26 (`V26PulseEvidence` / `V26RespiratoryEvidence`)**: Shadow estimators remain experimental until paired physical validation against V18/WHOOP.
