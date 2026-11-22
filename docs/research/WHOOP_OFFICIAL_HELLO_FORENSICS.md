# WHOOP Official BLE HELLO Protocol — Forensic Investigation Report

**Document ID:** `WHOOP_OFFICIAL_HELLO_FORENSICS.md`
**Investigation Date:** November 22, 2026
**Target Repository:** `ribhupanwar/whoop-mg-client` (STRAP)
**Branch:** `research/hello-forensics`

---

## 1. Binary Identity and Analysis Environment

### 1.1 Analyzed Binaries (from existing research)

| Binary | Version | Build | Mach-O UUID | SHA-256 | Status |
|--------|---------|-------|-------------|---------|--------|
| Primary (Ghidra) | 5.78.0 | 772673 | `ebcf159f-2cf1-3c41-9075-62430d06e07c` | `0DC7B082103E7FEFD03FBD466E45E8D23B65780C28A18134F9039E83F204C638` | Loaded in Ghidra |
| Reference | 5.75.0 | 738478 | `589a48d9-edcf-3d2c-8e58-7f9272624455` | `04013F93E469C304A15A33BE6BFE58D690E8D7F7D2B7BD843CBEBEA279B113B9` | Available |

**Note:** WHOOP 5.80.2 binary (209,853,712 bytes) referenced in `docs/research/whoop_5802/BLE_SYNC_FORENSICS.md` — **not yet loaded in Ghidra project for HELLO-specific analysis**.

### 1.2 Analysis Environment
- **Ghidra Version:** 12.2_PUBLIC
- **Architecture:** ARM64 (AArch64) Mach-O 64-bit executable

---

## 2. Ghidra Symbols and Function Addresses (5.78.0 Binary)

| Symbol / Function | Address | Binary Section | Notes |
|-------------------|---------|----------------|-------|
| `processCommandDidGetHelloPacket:` | `0x1003cd0a4` | `__TEXT,__text` | Response handler for HELLO packet |
| `processCommandDidGetHelloInfoWithSerial:signature:boardId:` | `0x1003ce124` | `__TEXT,__text` | Serial/signature/boardId ingestion |
| `FUN_1003cd110` | `0x1003cd110` | `__TEXT,__text` | Subroutine: writes CLIENT_HELLO (0x91) |
| `_TtC5Whoop35BluetoothPairingConnectingViewModel` | — | — | ViewModel containing above methods |

**Verification Status:** Addresses verified against 5.78.0 binary (Mach-O UUID `ebcf159f...`). **Not yet verified against 5.80.2 binary** — addresses may differ due to ASLR/image base changes and code modifications between versions.

---

## 3. Call Graph: HELLO Construction → BLE Write (from 5.78.0 decompilation)

```
BluetoothPairingConnectingViewModel
    └─ processCommandDidGetHelloPacket: (0x1003cd0a4)
          └─ processCommandDidGetHelloInfoWithSerial:signature:boardId: (0x1003ce124)
                └─ FUN_1003cd110
                      └─ WHPBLECommandManager / SharedSequencer
                            └─ Write to characteristic fd4b0002 (commandTo)
                                  Opcode: 0x91 (CLIENT_HELLO)
                                  Sequence: monotonic 1-byte (SharedSequencer)
                                  Framing: Gen5 (0xAA 0x15 prefix, seq, opcode, payload, CRC)
```

**Evidence Classification:** `PARTIAL` — Call graph traced from response handler backward to write operation. **Forward trace (construction → write) not fully recovered** — the exact function that *constructs* the HELLO request payload before calling `FUN_1003cd110` has not been identified in the 5.78.0 binary.

---

## 4. HELLO Request Packet Format

### 4.1 STRAP Implementation (Current)

| Field | Value | Source |
|-------|-------|--------|
| Command Opcode | `0x91` (`CLIENT_HELLO`) | `BandUUIDs.swift:55` |
| Request Body | `[0x01]` | `BandLink.swift:1755` |
| Packet Type | Gen5 framed command | `BandPacket.command = 0x23` |
| Characteristic | `fd4b0002` (commandTo) | `BandUUIDs.swift:6` |
| Response On | `fd4b0003` (commandFrom) | `BandUUIDs.swift:7` |
| Sequence | Monotonic UInt8 | `BandLink.swift:1976` |
| Timeout | 30 seconds | `BandLink.swift:2024` |

### 4.2 Official WHOOP Binary Evidence (5.78.0)

| Aspect | Evidence | Classification |
|--------|----------|----------------|
| Opcode `0x91` used for HELLO | `FUN_1003cd110` writes command `0x91` | `BINARY_VERIFIED` |
| Gen5 framing (`0xAA 0x15`) | `SharedSequencer` / `WHPBLECommandManager` at `0x9777076` | `BINARY_VERIFIED` |
| Sequence number monotonic | `SharedSequencer` increments per command | `BINARY_VERIFIED` |
| Response on `fd4b0003` | `commandFrom` characteristic subscribed before HELLO | `BINARY_VERIFIED` |
| **Request payload `[0x01]`** | **Not directly observed in decompilation** | `HYPOTHESIS` |
| **HelloPacketRev3/Rev4 existence** | **Symbols not found in 5.78.0 binary** | `NOT FOUND` |
| **144-byte resource** | **Not located in binary** | `NOT FOUND` |

### 4.3 Gap Analysis: Request Payload

The STRAP implementation sends a single-byte body `[0x01]`. The official binary's `FUN_1003cd110` is confirmed to write opcode `0x91`, but **the exact payload construction has not been traced in the decompilation**. The `[0x01]` body in STRAP may be:
- Correct (minimal HELLO request)
- Incomplete (missing protocol revision, nonce, device info)
- Incorrect (different byte value or multi-byte structure)

**Conclusion:** Request payload format **NOT CONFIRMED** from binary.

---

## 5. HELLO Response Packet Format

### 5.1 STRAP Implementation (Current)

`BandHelloExchange.receive()` validates:
```swift
frame.count >= 5 &&
frame[0] == BandPacket.commandResponse (0x24) || frame[0] == BandPacket.puffinCommandResponse (0x26) &&
frame[2] == BandCommand.clientHello.rawValue (0x91) &&
frame[3] == sequence &&
frame[4] == 1  // Success status
```

No parsing of serial, signature, or boardId from response payload.

### 5.2 Official WHOOP Binary Evidence (5.78.0)

| Response Field | Evidence | Classification |
|----------------|----------|----------------|
| Response opcode `0x91` | `processCommandDidGetHelloPacket:` checks `frame[2] == 0x91` | `BINARY_VERIFIED` |
| Sequence matching | Implied by `SharedSequencer` correlation | `BINARY_VERIFIED` |
| Success status byte | STRAP checks `frame[4] == 1`; binary not fully traced | `PARTIAL` |
| **Serial number** | `processCommandDidGetHelloInfoWithSerial:signature:boardId:` signature implies ingestion | `PARTIAL` |
| **Cryptographic signature** | Method name includes `signature` parameter | `PARTIAL` |
| **Board ID / Hardware revision** | Method name includes `boardId` parameter | `PARTIAL` |
| **Signature verification logic** | **Not located in decompilation** | `NOT FOUND` |
| **Authentication completion condition** | `hrBondConfirmed` set after response in STRAP; binary logic not traced | `NOT FOUND` |
| **Full response payload layout** | **Not recovered** | `NOT FOUND` |

**Conclusion:** Response handler entry point identified, but **full payload parsing and validation logic not recovered**.

---

## 6. HelloPacketRev3 / HelloPacketRev4 Investigation

### 6.1 Symbol Search Results (5.78.0 Binary)

| Symbol | Found? | Notes |
|--------|--------|-------|
| `HelloPacket` | No | — |
| `HelloPacketRev3` | No | — |
| `HelloPacketRev4` | No | — |
| `HelloResponsePacket` | No | — |
| `HelloResponsePacketRev3` | No | — |
| `HelloResponsePacketRev4` | No | — |
| `sendGetHelloPacket` | No | — |
| `getHelloPacket` | No | — |
| `HelloSending` | No | — |

### 6.2 String Search Results

| Search Term | Matches | Context |
|-------------|---------|---------|
| `HelloPacket` | 0 | — |
| `hello.*rev` | 0 | — |
| `144` (byte length) | Multiple | Unrelated constants (timers, array sizes) |

### 6.3 144-Byte Resource Claim

Previous investigation suggested 144-byte `HelloPacketRev3/Rev4` resources. **Verification in 5.78.0 binary: NOT FOUND**. No 144-byte data structures referenced by HELLO-related functions. If they exist, they may be:
- In 5.80.2 binary only (not yet analyzed for HELLO)
- Swift metadata / type descriptors (not wire packets)
- Misidentified / incorrect claim

**Classification:** `NOT FOUND` — no evidence in 5.78.0 binary.

---

## 7. Authentication State Machine

### 7.1 STRAP State Machine

```
.unpaired → .scanning → .deviceFound → .connecting → .authenticating → .connected
                                              ↑              ↓
                                              └──── timeout (30s, max 3 retries)
```

- `.authenticating`: CLIENT_HELLO sent, awaiting response
- Success: `hrBondConfirmed = true`, status → `.connected`
- Failure: 3 timeouts → `.failed` / `.unpaired`

### 7.2 Official WHOOP Binary (Inferred)

From `BluetoothPairingConnectingViewModel`:
1. Connect to peripheral
2. Subscribe to `fd4b0003` (commandFrom), `fd4b0004` (events)
3. Write CLIENT_HELLO (0x91)
4. Receive response on `fd4b0003` → `processCommandDidGetHelloPacket:`
5. Extract serial, signature, boardId → `processCommandDidGetHelloInfoWithSerial:signature:boardId:`
6. **Verify signature** (logic not recovered)
7. **Validate serial** (logic not recovered)
8. Persist `preferredBandID` (UUID string) to UserDefaults

**Missing Links:**
- Signature verification algorithm (ECDSA? Ed25519? Custom?)
- Challenge/nonce exchange (if any)
- Board ID validation logic
- Failure/disconnect behavior on auth failure

---

## 8. Official WHOOP vs STRAP Comparison

| Field | Official WHOOP (5.78.0) | STRAP (Current) | Evidence |
|-------|-------------------------|-----------------|----------|
| Command opcode | `0x91` (CLIENT_HELLO) | `0x91` | `BINARY_VERIFIED` |
| Header / Framing | Gen5 (`0xAA 0x15` prefix, seq, opcode, payload, CRC) | Gen5Frame.build() | `BINARY_VERIFIED` |
| Request payload | **Unknown** (not traced) | `[0x01]` | `HYPOTHESIS` |
| Packet length | **Unknown** | Variable (framing + 1 byte body) | `NOT FOUND` |
| GATT Characteristic (TX) | `fd4b0002` (commandTo) | `fd4b0002` | `BINARY_VERIFIED` |
| GATT Characteristic (RX) | `fd4b0003` (commandFrom) | `fd4b0003` | `BINARY_VERIFIED` |
| Response parser | `processCommandDidGetHelloPacket:` → `processCommandDidGetHelloInfoWithSerial:signature:boardId:` | `BandHelloExchange.receive()` (minimal) | `PARTIAL` |
| Sequence validation | `SharedSequencer` echo | `frame[3] == sequence` | `BINARY_VERIFIED` |
| Auth verification | Signature, serial and board ID appear as handler parameters | Existing response handling | Validation behavior unverified |
| Retry/timeout | **Not fully traced** (ViewModel likely handles) | 30s timeout, 3 retries, then disconnect | `HYPOTHESIS` |
| Rev3 vs Rev4 | **Symbols not found** | Not implemented | `NOT FOUND` |

---

## 9. BLE Capture Correlation

### 9.1 Available Captures
- **Repository captures:** None found in `ribhupanwar/whoop-mg-client` repository
- **Local captures:** Referenced in research docs (e.g., `sleep-1795020250-...csv` for telemetry) but **no HELLO handshake captures identified**
- **Physical BLE sniffer captures:** **Not available** — required for live wire validation

### 9.2 Capture Gap
Without a captured HELLO handshake (TX + RX), we cannot:
- Verify the exact request payload bytes on the wire
- Verify the exact response payload structure
- Correlate binary call graph with actual traffic
- Confirm Gen5 framing details for HELLO specifically

**Capture evidence:** No verified HELLO capture is available.

---

## 10. Evidence Classification Summary

| Conclusion | Classification | Notes |
|------------|----------------|-------|
| Opcode `0x91` = CLIENT_HELLO | `BINARY_VERIFIED` | Direct from `FUN_1003cd110` |
| Gen5 framing used | `BINARY_VERIFIED` | `SharedSequencer` / `WHPBLECommandManager` |
| Sequence number monotonic | `BINARY_VERIFIED` | `SharedSequencer` |
| Response on `fd4b0003` | `BINARY_VERIFIED` | Subscription before HELLO write |
| Response handler entry | `BINARY_VERIFIED` | `processCommandDidGetHelloPacket:` at `0x1003cd0a4` |
| Serial/signature/boardId ingestion | `PARTIAL` | Method signature implies it; parsing not traced |
| Request payload = `[0x01]` | `HYPOTHESIS` | STRAP assumption; not in binary |
| HelloPacketRev3/Rev4 exist | `NOT FOUND` | No symbols, no 144-byte resources in 5.78.0 |
| Signature verification logic | `NOT FOUND` | Not located in decompilation |
| Full response payload layout | `NOT FOUND` | Not recovered |
| Authentication state machine | `PARTIAL` | Entry points known; transitions not fully traced |
| Live wire capture | `NOT FOUND` | No HELLO handshake captures available |

---

## 11. Missing Evidence and Required Next Investigation

| Missing Item | Required For | Next Step |
|--------------|--------------|-----------|
| **5.80.2 binary loaded in Ghidra** | Version-parity verification; Rev3/Rev4 may exist only in newer version | Inspect the 5.80.2 executable in Ghidra |
| **Forward call graph: HELLO construction → write** | Exact request payload bytes | Trace from `BluetoothPairingConnectingViewModel` connection logic → `FUN_1003cd110` |
| **Response payload parsing in `processCommandDidGetHelloInfoWithSerial:signature:boardId:`** | Serial/signature/boardId extraction, signature verification | Decompile `0x1003ce124` fully |
| **HelloPacketRev3/Rev4 symbols or resources** | Protocol version differences | Search 5.80.2 binary for these symbols |
| **Physical BLE capture of HELLO handshake** | Wire-format ground truth | Capture with BLE sniffer (nRF Sniffer / Ellisys) during official WHOOP app pairing |
| **Signature verification algorithm** | Auth replication | Trace crypto calls from response handler |
| **Rev3 vs Rev4 behavioral difference** | Protocol compatibility | Compare 5.75.0, 5.78.0, 5.80.2 binaries |

---

## 12. Does STRAP's Current Hello Implementation Match?

| Aspect | Match? | Confidence |
|--------|--------|------------|
| Opcode | ✅ Yes | High (`BINARY_VERIFIED`) |
| Framing | ✅ Likely | High (Gen5 used for all commands) |
| Characteristic | ✅ Yes | High (`BINARY_VERIFIED`) |
| Sequence handling | ✅ Yes | High (`BINARY_VERIFIED`) |
| **Request payload** | ❓ **Unknown** | **Low** — not verified |
| **Response parsing** | ❌ **Incomplete** | **Low** — STRAP only checks sequence + status byte |
| **Auth verification** | ❌ **Unknown** | Official verification behavior is unresolved |
| **Rev3/Rev4 handling** | ❌ **Not implemented** | **N/A** — not found in binary |

Static observations suggest overlap in opcode, framing, characteristic and sequence handling. Request payload, response layout and authentication behavior require wire evidence.

---

## 13. Final Determination

### HELLO PARTIALLY FOUND — MISSING EVIDENCE

**Recovered:**
- Command opcode `0x91` (CLIENT_HELLO) — `BINARY_VERIFIED`
- Gen5 framing with monotonic sequence — `BINARY_VERIFIED`
- GATT characteristics: TX `fd4b0002`, RX `fd4b0003` — `BINARY_VERIFIED`
- Response handler entry point: `processCommandDidGetHelloPacket:` — `BINARY_VERIFIED`
- Serial/signature/boardId ingestion method signature — `PARTIAL`

**Not Recovered (Blockers):**
1. **Exact HELLO request payload construction** — forward call graph not traced
2. **Full response payload layout and parsing** — `processCommandDidGetHelloInfoWithSerial:signature:boardId:` not fully decompiled
3. **Signature verification algorithm** — crypto calls not located
4. **HelloPacketRev3/Rev4 existence and format** — symbols not found in 5.78.0; 5.80.2 not yet analyzed
5. **Live BLE capture of handshake** — no wire-format ground truth

**Required to Complete:**
1. Load WHOOP 5.80.2 binary in Ghidra and repeat HELLO-specific analysis
2. Trace forward call graph from connection initiation → HELLO write
3. Fully decompile `processCommandDidGetHelloInfoWithSerial:signature:boardId:` at `0x1003ce124` (5.78.0) / equivalent in 5.80.2
4. Obtain physical BLE capture of official WHOOP app pairing handshake

---

## 14. Files Inspected

- `docs/research/whoop-ble-pairing-reconnection-ghidra-analysis.md`
- `docs/research/WHOOP_GHIDRA_EVIDENCE_MATRIX.md`
- `docs/research/WHOOP_FINAL_REVERSE_ENGINEERING_GAP_AUDIT.md`
- `docs/research/ghidra-findings-index-2026-11-15.md`
- `docs/research/whoop_5802/BLE_SYNC_FORENSICS.md`
- `docs/research/WHOOP_BLE_FIELD_VALIDATION.md`
- `ios/Strap/Band/BandLink.swift` (STRAP implementation)
- `ios/Strap/Band/BandUUIDs.swift` (STRAP opcodes/UUIDs)

---

## 15. Recommendation for STRAP

**Do NOT modify production BLE code** until:
1. 5.80.2 binary analysis completes
2. Physical BLE capture validates wire format
3. Signature verification logic is recovered

The 5.78.0 analysis identifies a handler that accepts serial, signature and board ID parameters. Their presence does not establish how the app verifies them or whether they affect STRAP pairing failures. The cause of intermittent pairing failures remains unverified.

---
