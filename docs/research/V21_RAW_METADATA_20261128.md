# V21 metadata evidence — 2026-11-28

User-provided WHOOP 5.80.2 report lists RawDataRev21 parse-error strings for accel/gyro ODR, range, flags, sample counts, bias X/Y/Z, and padding. String presence does not establish their offsets, widths, units, firmware-specific behavior or scaling.

Pinned OpenStrap protocol dc699ce491c5eec4c924fafe8e29c637ea758b5a, lib/src/gen5_records.dart, confirms 1232-byte inner, counts at 16/622, axis offsets 20/220/420 and 632/832/1032, independent counts 1...100, existing fixed scales. It does not independently decode ODR, range or bias. Unused axis slots can contain stale data; do not treat them as zero padding.

This patch exposes the exact unclassified non-axis spans 13..<20 and 620..<632 in the existing historical/live motion diagnostics. Existing routes, identity, accepted counts, axes, scales, cadence, step consumer, physiology, sleep, history and signing remain unchanged. No new BLE commands. Synthetic tests assert byte retention and unchanged motion output. No real-device V21 metadata calibration or accuracy claim.

Next evidence required: parser function and load/advance instructions for each field, width, signedness, endian, units and enum mapping; paired raw packets from real firmware; verify bias and sample-rate effects before proposing production behavior.
