# Consolidated native sensor integration — V18 / V20 / V21 / V22 / V26

This extends PR #314; builds on existing decoders and raw capture, does not duplicate the protocol implementations. Evidence: existing Gen5IMUBuffer, Gen5V20Record, Gen5V22Record, Gen5V26Record and V18Decoder plus user-provided protocol research. The WHOOP 5.80.2 decompilation and physical-device comparison remain incomplete.

| Record | Production consumption in this batch | Not established |
| --- | --- | --- |
| V18 | Source-specific timestamp, recent measured cadence, pSNR/wrist diagnostics | Quality threshold for HRV, guaranteed live cadence |
| V20 | Decoded historical optical payload byte count and band timestamp | ADC channel layout/calibration, PPG/SpO2 algorithm |
| V21 / IMU shape | Per-block centered acceleration vector RMS (g), gyro vector RMS (deg/s), independent declared counts and timestamp | Sleep/activity classifier thresholds, timestamp alignment across sources |
| V22 | Tag and known/unknown tag counts | Complete tag payload semantics |
| V26 | Raw delta RMS in ADC units, count, first ADC and acceleration delta retained in summary | Waveform reconstruction semantics, channel mapping and calibration |

Counts are per drain, not unique records or coverage seconds. Replayed frames may contribute to counts; an older timestamp cannot replace a newer summary. The bounded summaries are in memory and use the existing raw capture for evidence. No new firmware commands, no changes to historical ACK or storage, no use of raw optical records as RR/HR. The current app may receive none of these deep records. Health diagnostics expose actual delivered data; unavailable is not zero.

Before using motion in sleep/activity/HRV/stress or optical data in calibrated metrics, capture real hardware and verify timing, sample/channel definitions, quality, and comparison against reference measurements. No claims of accuracy gains yet. Native iOS CI and hardware testing required.
