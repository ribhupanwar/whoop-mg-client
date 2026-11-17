# Gen5 record audit

Reference: OpenStrap/protocol `fbadb5b`, `lib/src/gen5_records.dart` and `constants.dart`. STRAP implementations use independently written code and synthetic fixtures; no third-party implementation or personal packet capture is copied.

| Format | Verified framing/geometry | STRAP treatment | Limits |
|---|---|---|---|
| V18 | Historical type 0x2F; existing header/biometrics/RR quality fields | Existing V18 decoder, source capture and tests | HR-based wearing is a proxy. Coarse band sleep envelope is not staging. Physiological accuracy still needs paired data. |
| V20 | Exact 2128-byte inner, version 20, five 422-byte blocks at 18, declared rate u16 at 15; per-block count <=50, metadata then two 50-slot signed 20-bit optical arrays | `Gen5OpticalBuffer`, raw metadata retained, only declared samples read | No calibrated oxygen/HR/RR from ADC counts. Gain/drive change between records; do not compare raw amplitudes or assume block 3 always IR. Malformed counts rejected, original frame retained. |
| V21 / IMU shape | Exact 1232 bytes; independent of version byte; counts at 16/622 in 1...100; axes at 20/220/420 and 632/832/1032 | `Gen5IMUBuffer`, signed samples, 1/4096 g and 2000/32768 dps | Reference nominal rate 100 Hz is not measured timing on this user's firmware. No interpolated per-sample timestamps. Verified routes 0x2F/0x2B; no assumption about 0x34 framing. |
| V22 | Exact 176 bytes, version 22, layout selector at 13, tags 1...6 documented | `Gen5ResearchBuffer` retains header/tag/original body, unknown tags retained as raw body | Research metadata/mirrors are not additional clinical readings. No invented names or calibrated clinical interpretation for unnamed fields. |
| V26 | Exact 76-byte optical waveform, version 26 | Existing `Gen5V26Record` and tests | Not a biometric RR record. No optical HRV inference. |

Historical dispatch recognizes motion and optical/research shapes before biometric decoding. Raw capture remains before dispatch and the pre-ACK durable persistence path remains in place. Recognition means a documented non-biometric record can be retained without treating it as an undecodable HR second; it does not create any HR, RR, sleep stage, wear, SpO2, temperature or Recovery input.

Type 47 (0x2F) is the verified historical record route. Canonical constants identify type 52 (0x34) as historical IMU stream, but this source does not establish a 0x34 payload decoder. Real payload/framing evidence is still required. Those frames remain raw; STRAP must not reuse the 0x2F header blindly.

The live 0x2B IMU shape can be decoded by the standalone decoder; current BandLink only recognizes the shape in its existing historical 0x2F dispatch. No new streaming command or notification is enabled. Device validation remains required for streaming/sampling rate and physical units, off-wrist/charging transitions, and changes across firmware. No BLE opcode or sensor threshold was guessed.
