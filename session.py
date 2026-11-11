"""Gen5 (WHOOP 5.0 / MG) session driver: bond, handshake, drain flash history.

Link sequence, from protocol facts observed on real hardware:
  1. Write CLIENT_HELLO (0x91, payload [0x01]) WITH RESPONSE to fd4b0002.
     This triggers the just-works bond.
  2. Subscribe to the notify characteristics once the link is authenticated.
  3. GET_DATA_RANGE (0x22) then SEND_HISTORICAL_DATA (0x16), both with EMPTY
     payloads on gen5 (gen4 sends a single 0x00).

Commands go one at a time, ~120ms apart. Every received frame is logged so
decoders can be developed offline without the band attached.

Keep Bluetooth OFF on your phone. BLE is one-central.
"""

import argparse
import asyncio
import json
import time
from contextlib import asynccontextmanager
from pathlib import Path

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError

from whoop.constants import Command, PacketType, build_command
from whoop.framing import GEN5_PROFILE, FrameReassembler, build_frame
from whoop.gatt import GEN5
from whoop.records import MAX_RR_MS, MIN_RR_MS

COMMAND_SPACING_S = 0.12
HR_MEASUREMENT_UUID = "00002a37-0000-1000-8000-00805f9b34fb"


def parse_standard_hr(data: bytes) -> tuple[int, list[int]] | None:
    """SIG heart-rate measurement (0x2A37): flags, uint8/uint16 HR, optional
    energy expended, then R-R in 1/1024 s. Mirrors StandardHeartRate.swift."""
    if len(data) < 2:
        return None
    flags = data[0]
    index = 1
    if flags & 0x01 == 0:
        bpm = data[index]
        index += 1
    else:
        if len(data) < 3:
            return None
        bpm = data[1] | (data[2] << 8)
        index = 3
    if flags & 0x08:
        index += 2
    rr: list[int] = []
    if flags & 0x10:
        while index + 1 < len(data):
            raw = data[index] | (data[index + 1] << 8)
            index += 2
            ms = round(raw * 1000.0 / 1024.0)
            if MIN_RR_MS <= ms <= MAX_RR_MS:
                rr.append(ms)
    return bpm, rr


class AuthRequired(RuntimeError):
    """The link is not bonded, so the proprietary service rejects the operation."""


async def find_band(timeout: float, address: str | None) -> str:
    if address:
        return address
    print(f"Scanning {timeout:.0f}s for a WHOOP band...")
    devices = await BleakScanner.discover(timeout=timeout, return_adv=True)
    for dev, adv in devices.values():
        if "whoop" in (dev.name or "").lower():
            print(f"  found {dev.name!r} at {dev.address} (rssi {adv.rssi})")
            return dev.address
    raise RuntimeError("No WHOOP band found. Turn Bluetooth OFF on your phone and retry.")


@asynccontextmanager
async def connect_band(address: str, attempts: int = 3, timeout: float = 45.0):
    """Connect with a bounded retry. WinRT needs the strap actively advertising
    at connect time, and a stale address cache raises DeviceNotFoundError, so
    each attempt resolves a fresh BLEDevice first. Yields a connected client."""
    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        device = await BleakScanner.find_device_by_address(address, timeout=20.0)
        target = device if device is not None else address
        client = BleakClient(target, timeout=timeout)
        try:
            await client.connect()
        except (TimeoutError, BleakError) as exc:
            last_exc = exc
            print(f"  connect attempt {attempt}/{attempts} failed: {type(exc).__name__}")
            try:
                await client.disconnect()
            except Exception:
                pass
            await asyncio.sleep(2.0)
            continue
        try:
            yield client
        finally:
            await client.disconnect()
        return
    raise RuntimeError(
        f"could not connect to {address} after {attempts} attempts"
    ) from last_exc


class Session:
    def __init__(self, client: BleakClient, log_path: Path) -> None:
        self.client = client
        self.log_path = log_path
        self.reassemblers = {
            uuid: FrameReassembler(GEN5_PROFILE) for uuid in GEN5.notifiable
        }
        self.frames: list[dict] = []
        self.seq = 1
        self.acks_sent = 0
        self.live_hr: list[dict] = []
        self._ack_queue: asyncio.Queue[bytes] = asyncio.Queue()
        self._t0 = time.monotonic()
        self._log = log_path.open("w", encoding="utf-8")

    def _on_notify(self, uuid: str):
        def handler(_char, data: bytearray) -> None:
            chunk = bytes(data)
            elapsed = round(time.monotonic() - self._t0, 4)
            self._log.write(
                json.dumps({"t": elapsed, "uuid": uuid, "chunk": chunk.hex()}) + "\n"
            )
            self._log.flush()
            for inner in self.reassemblers[uuid].feed(chunk):
                record = {
                    "t": elapsed,
                    "uuid": uuid,
                    "packet_type": inner[0] if inner else None,
                    "seq": inner[1] if len(inner) > 1 else None,
                    "opcode": inner[2] if len(inner) > 2 else None,
                    "len": len(inner),
                    "inner": inner.hex(),
                }
                self.frames.append(record)
                self._log.write(json.dumps({"frame": record}) + "\n")
                self._log.flush()
                ptype = record["packet_type"]
                try:
                    label = PacketType(ptype).name
                except ValueError:
                    label = f"0x{ptype:02X}" if ptype is not None else "?"
                print(f"  <- {label:<24} opcode={record['opcode']} len={len(inner)}")
                if (
                    inner[0] == PacketType.REALTIME_DATA
                    and len(inner) > 8
                    and 25 <= inner[8] <= 230
                ):
                    self._record_live_hr(inner[8], "vendor", [])
                if (
                    inner[0] == PacketType.METADATA
                    and len(inner) >= 21
                    and inner[2] == 2  # HISTORY_END
                ):
                    token = inner[13:21]
                    expected = int.from_bytes(inner[9:13], "little")
                    self._ack_queue.put_nowait(token)
                    print(
                        f"     HISTORY_END expected={expected} token={token.hex()} -> ACK queued"
                    )
        return handler

    async def ack_worker(self) -> None:
        """Echo each HISTORY_END token back so the offload advances."""
        while True:
            token = await self._ack_queue.get()
            try:
                await self.send(Command.HISTORICAL_DATA_RESULT, b"\x01" + token)
                self.acks_sent += 1
                print(f"     ACK sent ({self.acks_sent} total)")
            except Exception as exc:
                print(f"     ACK failed: {type(exc).__name__}: {exc}")
            finally:
                self._ack_queue.task_done()

    async def send(self, opcode: int, body: bytes = b"", *, response: bool = True) -> None:
        inner = build_command(opcode, body, seq=self.seq)
        self.seq = (self.seq + 1) & 0xFF
        frame = build_frame(inner, GEN5_PROFILE)
        print(f"  -> cmd 0x{opcode:02X} seq={inner[1]} {frame.hex()}")
        try:
            await self.client.write_gatt_char(GEN5.cmd_to, frame, response=response)
        except BleakError as exc:
            if "Authentication" in str(exc) or "Encryption" in str(exc):
                raise AuthRequired(str(exc)) from exc
            raise
        await asyncio.sleep(COMMAND_SPACING_S)

    async def subscribe_all(self) -> list[str]:
        subscribed = []
        for uuid in GEN5.notifiable:
            try:
                await self.client.start_notify(uuid, self._on_notify(uuid))
                subscribed.append(uuid)
            except BleakError as exc:
                if "Authentication" in str(exc) or "Encryption" in str(exc):
                    raise AuthRequired(str(exc)) from exc
                print(f"  subscribe {uuid[:8]} failed: {exc}")
        return subscribed

    def _record_live_hr(self, bpm: int, source: str, rr: list[int]) -> None:
        elapsed = round(time.monotonic() - self._t0, 4)
        self.live_hr.append({"t": elapsed, "bpm": bpm, "source": source, "rr": rr})
        rr_text = f" rr={rr}" if rr else ""
        print(f"  LIVE HR {bpm} bpm ({source}){rr_text}")

    async def subscribe_standard_hr(self) -> bool:
        def handler(_char, data: bytearray) -> None:
            reading = parse_standard_hr(bytes(data))
            if reading is None:
                return
            bpm, rr = reading
            self._record_live_hr(bpm, "2a37", rr)

        try:
            await self.client.start_notify(HR_MEASUREMENT_UUID, handler)
            return True
        except BleakError as exc:
            print(f"  standard HR subscribe failed: {exc}")
            return False

    async def unsubscribe_all(self) -> None:
        for uuid in GEN5.notifiable:
            try:
                await self.client.stop_notify(uuid)
            except Exception:
                pass

    def close(self) -> None:
        self._log.close()


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address")
    parser.add_argument("--scan-timeout", type=float, default=15.0)
    parser.add_argument("--seconds", type=float, default=30.0, help="history drain window")
    parser.add_argument("--out", default="session_capture.jsonl")
    parser.add_argument(
        "--hello-only",
        action="store_true",
        help="just write CLIENT_HELLO to trigger the bond, then exit",
    )
    parser.add_argument(
        "--realtime",
        action="store_true",
        help="enable the live HR stream (0x0E + 0x03 + 2A37) and collect live beats; no history drain",
    )
    args = parser.parse_args()

    address = await find_band(args.scan_timeout, args.address)
    print(f"\nConnecting to {address} ...")

    async with connect_band(address) as client:
        print(f"Connected. MTU={client.mtu_size}\n")
        session = Session(client, Path(args.out))
        ack_task: asyncio.Task | None = None
        try:
            print("=== Step 1: subscribe before any command ===")
            print("The strap replies to CLIENT_HELLO immediately; subscribing after")
            print("sending it loses the identity response and stalls the offload.")
            try:
                subscribed = await session.subscribe_all()
            except AuthRequired:
                print("  not bonded yet - writing CLIENT_HELLO to trigger the bond")
                await session.send(Command.HELLO_GEN5, b"\x01", response=True)
                await asyncio.sleep(1.0)
                subscribed = await session.subscribe_all()
            print(f"  subscribed to {len(subscribed)}/{len(GEN5.notifiable)}\n")
            if not subscribed:
                raise AuthRequired("no notify characteristic could be subscribed")

            print("=== Step 2: CLIENT_HELLO ===")
            await session.send(Command.HELLO_GEN5, b"\x01", response=True)
            await asyncio.sleep(0.5)

            if args.hello_only:
                print("--hello-only: stopping after the handshake.")
                return 0

            if args.realtime:
                print("\n=== Step 3 (realtime): enable the live HR stream ===")
                await session.send(Command.SET_GENERIC_HR_PROFILE, b"")
                await session.send(Command.TOGGLE_REALTIME_HR, b"\x01")
                std = await session.subscribe_standard_hr()
                print(f"  standard 2A37 subscribed: {std}")
                print(f"\nCollecting live HR for {args.seconds:.0f}s ...")
                await asyncio.sleep(args.seconds)
                print("\n=== Live HR summary ===")
                print(f"  live samples: {len(session.live_hr)}")
                if session.live_hr:
                    bpms = [s["bpm"] for s in session.live_hr]
                    print(f"  bpm min={min(bpms)} max={max(bpms)} mean={sum(bpms) / len(bpms):.1f}")
                    sources: dict[str, int] = {}
                    for s in session.live_hr:
                        sources[s["source"]] = sources.get(s["source"], 0) + 1
                    print(f"  by source: {sources}")
                    print(f"  R-R beats carried: {sum(len(s['rr']) for s in session.live_hr)}")
                else:
                    print("  NO live HR packets received.")
                return 0

            print("\n=== Step 3: request data range, then drain history ===")
            ack_task = asyncio.create_task(session.ack_worker())
            await session.send(Command.GET_DATA_RANGE, b"")
            await session.send(Command.SEND_HISTORICAL_DATA, b"")

            print(f"\nCollecting for {args.seconds:.0f}s ...")
            await asyncio.sleep(args.seconds)
        except AuthRequired as exc:
            print(f"\nBLOCKED - link is not authenticated: {exc}")
            print("\nThe proprietary fd4b service requires a bonded link.")
            print("Pair the strap in Windows Settings > Bluetooth & devices >")
            print("Add device > Bluetooth > WHOOP MG, then re-run this script.")
            return 2
        finally:
            if ack_task is not None:
                ack_task.cancel()
                try:
                    await ack_task
                except asyncio.CancelledError:
                    pass
            await session.unsubscribe_all()
            session.close()

    print(f"\n=== Summary ===")
    print(f"  complete frames decoded: {len(session.frames)}")
    print(f"  HISTORY_END ACKs sent:   {session.acks_sent}")
    counts: dict[str, int] = {}
    for frame in session.frames:
        try:
            label = PacketType(frame["packet_type"]).name
        except ValueError:
            label = f"0x{frame['packet_type']:02X}"
        counts[label] = counts.get(label, 0) + 1
    for label, count in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"    {label:<26} {count}")
    for uuid, reasm in session.reassemblers.items():
        if reasm.bad_frames or reasm.dropped_bytes or reasm.pending:
            print(
                f"  {uuid[:8]}: bad_frames={reasm.bad_frames} "
                f"dropped_bytes={reasm.dropped_bytes} pending={reasm.pending}"
            )
    print(f"  raw capture -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))