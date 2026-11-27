# STRAP native utilization master report

Snapshot from 2026-11-27. Main was `273c7b57521c25387f50946ac1fbae37054150d4`. This is a partial capability inventory with one implementation batch. It inherits detailed field evidence from the linked reports and records where this pass could independently verify it.

## Existing work and release gates

| PR | Exact head observed | State and scope |
|---|---|---|
| #296 | `45918960b00c7255b57c8304708729bc0c9e0704` | Draft, merge conflicts in Home, six protocol jobs and iOS passed on that head |
| #314 | `ef479239f7e0a4b3e5d237930b42f52ee593164a` | Draft, clean, six protocol jobs and iOS passed. Source-specific snapshot freshness, workout cadence and deep-telemetry snapshot. This batch builds on its existing consumer |
| #315 | `8dcb7bb3b080ddc5e8af93dfb9f859b364fa4fed` | Draft, six protocol jobs passed. iOS was running when checked. Passive ECG diagnostics, BLE contact gating, Memfault routing and discovery-only 0008/0009 |

Main contains #311 at `3ee32be` (workout and Lock Screen), #312 at `a13b5ee` (sleep lifecycle and stress freshness) and #313 at `273c7b5` (command responses, native quality snapshot and background sync). The #314 and #315 heads merged cleanly in a local Git merge-tree check. That check establishes textual compatibility only. Draft status and lack of recorded approvals prevented eligibility for release. Open issues #252 and #214 still require sensor and sleep-boundary evidence. Closed #160, #147, #136 and #126 cover work already integrated.

Main [protocol jobs](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/46005003553), [iOS workflow](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/46005003856) and [unsigned IPA](https://github.com/ribhupanwar/whoop-mg-client/actions/runs/46005003856/artifacts/15202850282) belong to the baseline commit.

## V20 history optical buffer

NOOP `2a1de7609843b095505274ad6fc811757210be80` provides capture-backed executable decoding and a real-frame oracle. OpenStrap Protocol `dc699ce491c5eec4c924fafe8e29c637ea758b5a` independently describes the same block tiling and rate field. The old 423-byte placeholder divided the payload at offset 13. The verified tiling starts at inner 18, with five 422-byte blocks at 18, 440, 862, 1284 and 1706. Add 8 for complete-frame offsets. Type 47, revision 20, 2128-byte inner and 2140-byte complete frame.

| Inner or block-relative offset | Length and type | Meaning and status |
|---|---|---|
| Inner 3, 7, 11 | u32, u32, u16 LE | Record index, band Unix seconds, raw subsecond. DECODED in the shared header |
| Inner 15 | 2 bytes u16 LE | Declared sample rate in Hz, zero treated as unavailable. DECODED |
| Inner 13–14, 17 | 3 bytes | Preserved header bytes. DISCOVERED |
| Block 0 | 1 byte u8 | Samples per detector slot, 0–50. DIAGNOSTIC UTILIZATION in offload validation |
| Block 1, 2, 4, 5 | u8, u16 LE, u8, u16 LE | Two raw source selectors and drive settings. DECODED |
| Block 7, 8, 12 | u8, u32 LE, i16 LE | Detector A selector, range and signed offset. DECODED |
| Block 14, 15, 19 | u8, u32 LE, i16 LE | Detector B selector, range and signed offset. DECODED |
| Block 21 and 221 | 200 bytes each, 50 i32 LE slots | Declared samples, signed 20-bit ADC codes in sign-extended containers. DIAGNOSTIC UTILIZATION for malformed codes, rails and flatline counts |
| Block 421 | 1 byte | Reserved byte preserved. DECODED |
| Emitter wavelength and optical calibration | — | BLOCKED WITH REASON. Sources agree on the layout and differ on wavelength and calibration interpretation. Same-block detector slots share an emitter configuration |

Swift `Gen5V20Record` and Python `decode_v20` preserve the existing raw body starting at inner 13. Malformed containers keep their position as missing. Exact rail values keep their codes and are counted separately. `BandLink` consumes the decoded record in the CRC-gated offload route, feeds aggregate counts into the #314 deep-telemetry snapshot at existing checkpoints and drain completion and preserves the existing raw archive and commit-before-ACK path. Counts describe observed frames and can include replay. Sample arrays are released per frame. Health diagnostics shows the aggregate for the last history sync. No UI update is emitted per block. No sensor score uses these optical data yet.

Both Python and Swift regression sources cover signed rails, invalid containers, fifth-block alignment, empty slots, signed detector offset, flatline and malformed declared count. Python replay through the existing frame reassembler matched both independently computed NOOP oracle records, all 300 declared ADC values and all compared metadata. Both declared 25 Hz. Zero malformed values, 42 rail values and zero flatline slots were observed. NOOP reports its corpus as WHOOP 5.0/MG firmware 50.40.1.0. This pass replayed published captures. On-device STRAP testing and additional firmware coverage are pending.

## Remaining route inventory

| Route | Current status and remaining evidence |
|---|---|
| Type 47 V18 | PRODUCTION UTILIZATION for summary HR, RR, steps, motion, sleep evidence and skin temperature. Candidate oxygen and optical source are diagnostic. Exact field offsets, sentinels, provenance and capture counts are in the [decoder parity audit](OPENSTRAP_NOOP_DECODER_PARITY_AUDIT.md) and [sensor audit](HEALTH_SENSOR_252_PRODUCTION_AUDIT.md). Activity class, auxiliary sensors, quality counters and candidate oxygen still need field-by-field consumer reconciliation. |
| R16 | DISCOVERED in NOOP ECG docs and executable R16 decoder. STRAP integration and matching MG captures remain outstanding. |
| R17 | DIAGNOSTIC UTILIZATION for passive filtered waveform via `MGEcgPacket`. Type 43/47, inner length 228, u16 count at 24, i16 slots from 26. Candidate HRV at inner 21–22 needs units, validity and spot-measurement provenance before use. |
| Type 43/47 V21 | DECODED by `Gen5IMUBuffer` and `decode_v21`. Counts at inner 16 and 622, axes 20/220/420 and 632/832/1032. 1/4096 g and 2000/32768 dps. Live source timing and validated feature integration for sleep, activity and stress remain outstanding. |
| V22 | DIAGNOSTIC UTILIZATION for 176-byte Type 47 recognition, raw retention and tag at inner 13. Separate layouts and version-9 optical evidence still require reconciliation. |
| Type 47 V26 | DECODED for 76-byte PIP record, anchor at 15, 24 i16 deltas at 19, motion at 67, state at 71, flag at 73 and morphology at 74. Reconstruction and timing still need consumer validation, including saturated deltas. |
| Type 40 and standard 2A37 | PRODUCTION UTILIZATION for HR/RR. #315 contains further 2A37 contact gating. Track cross-source beat identity and stale readings against physical replay before changing recovery. |
| Type 49 | PRODUCTION UTILIZATION for history offload. End token inner 13–20. Durable raw storage before ACK is covered by the existing history architecture. |
| Rev10, Type 51/52 | DISCOVERED. Model-specific routes and payload semantics need verification before use. #315 reports Type 52 observations. |
| FD4B0001–0005 | PRODUCTION UTILIZATION for service, command TX/RX, events and data. #313 covers command responses and iOS background processing. See the [implementation report](STRAP_NATIVE_BAND_IMPLEMENTATION_REPORT.md) for source paths. |
| FD4B0007–0009 | DISCOVERED. #315 isolates Memfault and adds discovery-only 0008/0009. Unknown payloads and characteristic behavior remain unresolved. |
| Sleep, workout and background | PRODUCTION UTILIZATION through the existing Swift pipeline. Wrist-on/off, interruption and final wake, reconnection and background execution still need a new physical-device trace with build, iOS and firmware versions recorded. |

## Reference pins

| Repository | Commit acquired |
|---|---|
| ryanbr/noop | `2a1de7609843b095505274ad6fc811757210be80` |
| OpenStrap/protocol | `dc699ce491c5eec4c924fafe8e29c637ea758b5a` |
| OpenStrap/edge | `a2d76654b16dc5c851bfdbbd39f3a59f53d59ad4` |
| OpenStrap/analytics | `a438df40b38a4586a52a68ab7e1c100fca111ccd` |
| OpenStrap/research | `c6be09c4021546e4693dcf74da25d7b793ff8a40` |
| LeonardSEO/wearable5.0 | `fd3e087970cbff236fee5dae7371b4bda0e6e3d7` |
| Asherlc/dofek | `902fd0e6b413a9ab020e4c7d84659f386b40fe2c` |
| b-nnett/goose | `ba9ae0280c9b5b9a1545baab8e944cb3b7563c62` |
| Rudra5417/whoop5-protocol | `769b8c3707e426c55516cd90a790bf0bb6dffb95` |
| Sophonbot0/whoop-vault | `bd43855e5d27f72125b0085a7f5f14beca585395` |
| mitchellfgibson/apollo-hacked | `67b17262b68c80a7a5a407cfb024a2be2b2e6e6c` |
| jaredwerba/whoop-ble-swift | GitHub returned Repository not found |
| johnmiddleton12/wearable | `890e0c96beb817ab0cec3aaf7d9a06c530025355` |
| satayutata/geniemax-core | `476550124c9e3fa08de40dbc99b11db4bd3186eb` |
| ribhupanwar/dsta | `bdee9cd087a2dd8564a7e60ac218cb2c010ebbd0` |
| ribhupanwar/Woop | `14bb3f8d40f0fe88841fd3dbbe6715f9c4ab7937` |

The pins record checkout acquisition. Full historical and implementation comparison across every repository and additional forks remains pending. The V20 implementation uses independently written code and wire facts from the pinned NOOP and OpenStrap sources. The external capture fixture was used in place and was not copied into STRAP.

## Inaccessible inputs

The Linux cloud workspace has no mounted Windows Downloads or `kilo-test` directory. The decrypted official 5.80.2 executable, Woop IPA, Ghidra project databases and reports stored only in those directories were unavailable. Cloud loopback port 8080 refused the Ghidra MCP connection. Repository research and its previously documented disassembly evidence remain available, but no fresh binary XREF evidence was generated. No paired band, personal export or personal capture bundle was attached for this pass.

Local Python discovery ran 480 tests with 478 passes and 2 skips. Swift/Xcode is absent locally. Swift tests, measured iOS performance, and a new unsigned IPA require the native CI run. On-device validation should cover offload and replay on 5.0 and MG, wrist/contact transitions and reconnect behavior, optical slot behavior across firmware, sleep continuation, and background workout and sync delivery.
