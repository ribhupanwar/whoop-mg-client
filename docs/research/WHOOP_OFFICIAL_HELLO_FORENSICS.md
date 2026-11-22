# WHOOP Official BLE HELLO Forensics

The 5.78.0 static-analysis notes below are version-specific. The official HELLO
request and response still lack a matched wire capture.

## Reported static observations

The original investigation used build 772673, Mach-O UUID
`ebcf159f-2cf1-3c41-9075-62430d06e07c`. These are disassembly landmarks for
reproduction.

| Symbol or location | Reported observation | Evidence limit |
| --- | --- | --- |
| `FUN_1003cd110` | Command path references opcode `0x91` | Forward request construction and payload are unresolved |
| `processCommandDidGetHelloPacket:` at `0x1003cd0a4` | Response-handler entry point | Full parser and dispatch conditions are unresolved |
| `processCommandDidGetHelloInfoWithSerial:signature:boardId:` at `0x1003ce124` | Handler accepts serial, signature and board ID | Parameters establish neither verification behavior nor an application-level authentication requirement |
| `SharedSequencer` and `WHPBLECommandManager` | Shared command sequencing and transport | HELLO-specific response correlation and framing require capture |
| Command characteristic subscription | Static notes identify command-channel subscription during setup | A subscription alone cannot establish which characteristic carries the HELLO response |

The data flow from connection setup through request construction and the data
flow from a received response through validation still need separate traces.
Addresses are specific to the analyzed binary. The 5.80.2 findings in the
[BLE sync notes](whoop_5802/BLE_SYNC_FORENSICS.md) do not establish HELLO parity.

## STRAP production behavior

- [BandUUIDs.swift](../../ios/Strap/Band/BandUUIDs.swift) defines the existing
  command characteristics and `clientHello` opcode.
- [BandLink.swift](../../ios/Strap/Band/BandLink.swift) queues the existing
  `[0x01]` request body. Its normal handshake waits for command notifications.
  The bond-probe branch has its own guard.
- `BandHelloExchange.receive` requires at least five bytes, a recognized
  response type, the HELLO opcode, the expected sequence and status byte 1.
  Confirmation requires both the accepted response and the completed write.
- [Gen5Frame.swift](../../ios/Strap/Protocol/Gen5Frame.swift) defines STRAP's
  frame header beginning with `0xAA 0x01`. This source confirms STRAP's
  encoding. Official HELLO framing on the wire remains unverified.

## Device verification

Capture an authorized WHOOP Gen5 or MG pairing and a reconnect with firmware
and app versions recorded. Correlate the request and response bytes with
characteristic UUIDs and notification readiness. Verify which fields and
sequence values the official implementation consumes before inferring a
response layout. Preserve existing STRAP timings, commands and history
behavior until version-specific evidence supports a change.
