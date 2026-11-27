# Remaining native route integration
Independent follow-up to #314, based on main 273c7b5. No destructive commands or subscription to unknown characteristics.

- Standard 2A37: explicit supported-but-not-detected contact flag excludes HR/RR from this source. Unsupported detection still permits existing behavior. No change to Type-40 or overnight estimator.
- FD4B0007: retain existing notification capture, count opaque notification bytes; do not dispatch as physiological frames.
- FD4B0008/0009: discovery only, no read, write or notification enable. Presence does not establish semantics.
- 0x2B / 0x34: count observed CRC-validated data-route frames, not unique records. Existing MG-only R17 passive decode remains; expose received packet/sample counts and receipt date, not ECG diagnosis or HRV.
- Hardware events: summarize known/unknown opcodes, distinguish status envelope from event, do not invent temperature payload or device state.
- Diagnostics are bounded per connection; UI updates throttled. Hardware validation and native CI pending.
- Rev10 firmware-specific layout, heartKeyHRV offset, Type52 semantics, 0008/0009 roles and optical calibration remain unverified. Need actual captures or parser evidence before enabling use. No accuracy percentage claimed.
