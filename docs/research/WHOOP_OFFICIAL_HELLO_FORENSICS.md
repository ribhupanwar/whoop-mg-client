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

---

## 20. 5.80.2 Deep Analysis — Selector Table and Data Reference Tracing

### 20.1 Analysis Method
- **Tool:** Ghidra 12.2_PUBLIC headless, WHOOP_Analysis5 project
- **Mode:** `-noanalysis` (raw memory + partial loader analysis, no auto-analysis)
- **Scripts:** `HelloProtocolSelectorRead.java`, `HelloProtocolKnownStrings.java`, `HelloProtocolDataRefs.java`, `HelloProtocolTargetedDisasm.java`
- **Constraint:** Full auto-analysis times out on 209MB binary due to ObjC type encoding errors; all analysis performed via targeted memory reads and disassembly

### 20.2 Verified Selector Table Entries (5.80.2)

| Selector Entry Address | Selector String | Referenced By (Data) |
|---|---|---|
| `0x10b4cc260` | `processCommandDidGetHelloPacket:` | `0x1091229D4`, `0x10910D3E4`, `0x109111D58`, `0x109122A24` |
| `0x10b4cc258` | `processCommandDidGetHelloInfoWithSerial:signature:boardId:` | `0x1091229E0`, `0x109111D64`, `0x109122A30` |
| `0x10b4d8b08` | `sendGetHelloPacketWithCompletionHandler:` | `0x109124DA0`, `0x1090E4914`, `0x109124E30`, `0x1090E03CC`, `0x109124EC0` |
| `0x10b396a00` | `didCallSendGetHelloPacket` | (no data refs found) |
| `0x10aca74b8` | `GetHelloPacket` | (no data refs found) |

**Classification:** `BINARY_VERIFIED` — selector strings and table entries confirmed via raw memory reads.

### 20.3 Verified Key String Addresses and Data References (5.80.2)

| String | Address | Data Reference(s) | Section |
|---|---|---|---|
| `helloResponse` | `0x109a88926` | `0x10B36AC78` | Swift metadata |
| `helloResponseTask` | `0x109a88940` | `0x10B3524C8` | Swift metadata |
| `strap_signature` | `0x1097b1e0e` | `0x10AD1B6E0`, `0x10AD1B718` | Swift metadata |
| `strapSerial` | `0x1098550e4` | `0x10AF28510` | Swift metadata |
| `boardId` | `0x109a2c151` | `0x10B356EB8` | Swift metadata |
| `lastConnectedStrapSerial` | `0x109a98a40` | `0x10B4C9F80`, `0x10B345CB0`, `0x10B38ABE8`, `0x10B402C00`, `0x10B4640A8` | Mixed |
| `lastConnectedStrapSignature` | `0x109a98a60` | `0x10B4C9F88`, `0x10B345CC0`, `0x10B38ABF8` | Mixed |
| `setLastConnectedStrapSignature:` | `0x109a46aad` | `0x10B4CF798` | Swift metadata |

**Classification:** `BINARY_VERIFIED` — all strings confirmed via raw memory reads at known addresses. All references are DATA type (Swift metadata/vtable indirection), not direct code references.

### 20.4 Crypto Function Analysis (5.80.2)

| Function | Address | Callers Found |
|---|---|---|
| `SecKeyCreateSignature` | `0x10908a798` | **0** (none in reference database) |
| `SecKeyVerifySignature` | `0x10908a7b0` | **0** (none in reference database) |

**Classification:** `NOT FOUND` — no callers in Ghidra's reference database. This may be because crypto calls occur through dynamic dispatch or in a separate framework.

### 20.5 Key Findings Summary

1. **Swift metadata indirection confirmed:** All HELLO selector and key string references are DATA type (Swift vtables/metadata), not direct code references. Standard reference tracing cannot follow these paths.

2. **No direct HELLO call sites found:** The call sites that load HELLO selector pages use OTHER selectors in those pages. The actual HELLO method calls go through Swift method dispatch.

3. **No crypto callers found:** `SecKeyCreateSignature` and `SecKeyVerifySignature` have zero callers in the reference database.

4. **FD4B UUID not found** as a direct string or byte pattern in the binary.

5. **helloResponse/helloResponseTask strings confirmed** at `0x109a88926` and `0x109a88940`, referenced by Swift metadata at `0x10B36AC78` and `0x10B3524C8`.

### 20.6 Remaining Blockers

1. **Swift metadata indirection** prevents direct code tracing to HELLO implementations
2. **No crypto callers found** — crypto may use dynamic dispatch
3. **No direct HELLO call sites** — method calls go through Swift dispatch
4. **No BLE capture available** — wire format unverified
5. **Ghidra auto-analysis limitation** — full analysis times out on 209MB binary

### 20.7 Recommended Next Steps

1. **Use Swift demangling tools** (e.g., `swift-demangle`, `dsdump`) to analyze Swift metadata
2. **Run Ghidra with selective analyzers** — disable ObjC type metadata analyzer
3. **Obtain physical BLE capture** of official WHOOP app pairing handshake
4. **Consider dynamic analysis** — run WHOOP app under debugger (Frida, LLDB)
5. **Compare 5.78.0 vs 5.80.2** using binary diff tools (BinDiff, Diaphora)
