"""Connect to the WHOOP MG and enumerate what it actually exposes.

Decisive question: is the proprietary fd4b service reachable on connection even
though the band advertises only the standard 0x180D Heart Rate Service? If yes,
full raw sensor access and flash history are available. If no, we are limited to
standard HR + R-R intervals, which still yields real HRV.

Keep Bluetooth OFF on your phone during this run. BLE is one-central.
"""

import argparse
import asyncio
import json
import math
import struct
import time
from pathlib import Path

from bleak import BleakClient, BleakScanner

from whoop.gatt import (
    BATTERY_SERVICE,
    DEVICE_INFO_SERVICE,
    GEN4,
    GEN5,
    HEART_RATE_SERVICE,
)

HR_MEASUREMENT = "00002a37-0000-1000-8000-00805f9b34fb"
BATTERY_LEVEL = "00002a19-0000-1000-8000-00805f9b34fb"

DIS_CHARS = {
    "00002a29-0000-1000-8000-00805f9b34fb": "manufacturer",
    "00002a24-0000-1000-8000-00805f9b34fb": "model",
    "00002a25-0000-1000-8000-00805f9b34fb": "serial",
    "00002a26-0000-1000-8000-00805f9b34fb": "firmware_revision",
    "00002a27-0000-1000-8000-00805f9b34fb": "hardware_revision",
    "00002a28-0000-1000-8000-00805f9b34fb": "software_revision",
}


def parse_hr_measurement(data: bytes) -> dict:
    """Bluetooth SIG Heart Rate Measurement (0x2A37)."""
    if not data:
        return {}
    flags = data[0]
    wide = flags & 0x01
    offset = 1
    hr = struct.unpack_from("<H" if wide else "<B", data, offset)[0]
    offset += 2 if wide else 1

    result = {
        "hr": hr,
        "sensor_contact": bool(flags & 0x06),
        "rr_ms": [],
    }
    if flags & 0x08:
        result["energy_expended_kj"] = struct.unpack_from("<H", data, offset)[0]
        offset += 2
    if flags & 0x10:
        while offset + 2 <= len(data):
            raw = struct.unpack_from("<H", data, offset)[0]
            offset += 2
            # RR is in 1/1024 second units.
            result["rr_ms"].append(round(raw * 1000.0 / 1024.0, 2))
    return result


def rmssd(rr_ms: list[float]) -> float | None:
    """Root mean square of successive differences — the standard HRV metric."""
    if len(rr_ms) < 2:
        return None
    diffs = [b - a for a, b in zip(rr_ms, rr_ms[1:])]
    return round(math.sqrt(sum(d * d for d in diffs) / len(diffs)), 2)


async def find_band(
    timeout: float, address: str | None, name_filter: str | None = None
) -> str:
    if address:
        return address
    print(f"Scanning {timeout:.0f}s for a WHOOP band...")
    devices = await BleakScanner.discover(timeout=timeout, return_adv=True)
    if name_filter:
        # Two straps of the same model are indistinguishable by service UUID;
        # the advertised name is what the owner recognises.
        for dev, adv in devices.values():
            name = (dev.name or adv.local_name or "").strip()
            if name_filter.lower() in name.lower():
                print(f"  found {name!r} at {dev.address} (rssi {adv.rssi})")
                return dev.address
        seen = sorted(
            {
                (dev.name or adv.local_name or "(no name)").strip()
                for dev, adv in devices.values()
            }
        )
        raise RuntimeError(
            f"No band named {name_filter!r}. Advertised names: {', '.join(seen) or 'none'}"
        )
    for dev, adv in devices.values():
        name = (dev.name or "").strip()
        if "whoop" in name.lower():
            print(f"  found {name!r} at {dev.address} (rssi {adv.rssi})")
            return dev.address
    for dev, adv in devices.values():
        for uuid in adv.service_uuids:
            if uuid.lower().startswith(("fd4b", "6108")):
                print(f"  found by service UUID at {dev.address}")
                return dev.address
    raise RuntimeError("No WHOOP band found. Turn Bluetooth OFF on your phone and retry.")


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address", help="skip scanning, connect directly")
    parser.add_argument(
        "--name", help="pick the band whose advertised name contains this text"
    )
    parser.add_argument("--scan-timeout", type=float, default=15.0)
    parser.add_argument("--seconds", type=float, default=20.0, help="HR stream duration")
    parser.add_argument("--out", default="capture.jsonl", help="raw notification log")
    args = parser.parse_args()

    address = await find_band(args.scan_timeout, args.address, args.name)
    print(f"\nConnecting to {address} ...")

    samples: list[dict] = []
    raw_log: list[dict] = []
    loop = asyncio.get_running_loop()
    started = loop.time()

    def on_hr(_char, data: bytearray) -> None:
        elapsed = round(loop.time() - started, 3)
        parsed = parse_hr_measurement(bytes(data))
        raw_log.append({"t": elapsed, "uuid": HR_MEASUREMENT, "raw": bytes(data).hex()})
        if parsed:
            samples.append({"t": elapsed, **parsed})

    def on_any(uuid: str):
        def handler(_char, data: bytearray) -> None:
            raw_log.append(
                {"t": round(loop.time() - started, 3), "uuid": uuid, "raw": bytes(data).hex()}
            )
        return handler

    async with BleakClient(address, timeout=30.0) as client:
        print(f"Connected. MTU={client.mtu_size}\n")
        print("=== GATT services exposed ===")

        proprietary = []
        hr_char_present = False
        for service in client.services:
            suuid = service.uuid.lower()
            tag = ""
            if suuid.startswith(GEN5.service[:8]):
                tag = "  <<< WHOOP GEN5 PROPRIETARY"
                proprietary.append(service)
            elif suuid.startswith(GEN4.service[:8]):
                tag = "  <<< WHOOP GEN4 PROPRIETARY"
                proprietary.append(service)
            elif suuid == HEART_RATE_SERVICE:
                tag = "  <<< standard Heart Rate Service"
            elif suuid == DEVICE_INFO_SERVICE:
                tag = "  (device info)"
            elif suuid == BATTERY_SERVICE:
                tag = "  (battery)"
            print(f"\n{service.uuid}{tag}")
            for char in service.characteristics:
                props = ",".join(char.properties)
                print(f"    {char.uuid}  [{props}]")
                if char.uuid.lower() == HR_MEASUREMENT:
                    hr_char_present = True

        print("\n=== Device identity ===")
        for service in client.services:
            if service.uuid.lower() == DEVICE_INFO_SERVICE:
                for char in service.characteristics:
                    label = DIS_CHARS.get(char.uuid.lower())
                    if label and "read" in char.properties:
                        try:
                            value = await client.read_gatt_char(char.uuid)
                            print(f"  {label}: {value.decode('utf-8', 'replace').strip()}")
                        except Exception as exc:
                            print(f"  {label}: read failed ({type(exc).__name__})")
            if service.uuid.lower() == BATTERY_SERVICE:
                for char in service.characteristics:
                    if char.uuid.lower() == BATTERY_LEVEL and "read" in char.properties:
                        try:
                            value = await client.read_gatt_char(char.uuid)
                            print(f"  battery: {value[0]}%")
                        except Exception as exc:
                            print(f"  battery: read failed ({type(exc).__name__})")

        print(f"\nProprietary WHOOP service reachable: {'YES' if proprietary else 'NO'}")

        if hr_char_present:
            print(f"\n=== Streaming heart rate for {args.seconds:.0f}s ===")
            await client.start_notify(HR_MEASUREMENT, on_hr)
            for service in proprietary:
                for char in service.characteristics:
                    if "notify" in char.properties:
                        try:
                            await client.start_notify(char.uuid, on_any(char.uuid))
                        except Exception as exc:
                            print(f"  subscribe {char.uuid} failed: {type(exc).__name__}")
            await asyncio.sleep(args.seconds)
            await client.stop_notify(HR_MEASUREMENT)

    Path(args.out).write_text(
        "\n".join(json.dumps(row) for row in raw_log) + "\n", encoding="utf-8"
    )

    print(f"\n=== Results ===")
    print(f"  HR notifications: {len(samples)}")
    print(f"  raw notifications logged: {len(raw_log)} -> {args.out}")
    if samples:
        hrs = [s["hr"] for s in samples if s.get("hr")]
        all_rr = [rr for s in samples for rr in s.get("rr_ms", [])]
        if hrs:
            print(f"  heart rate: min={min(hrs)} max={max(hrs)} mean={sum(hrs)/len(hrs):.1f} bpm")
        print(f"  R-R intervals captured: {len(all_rr)}")
        if all_rr:
            print(f"  R-R range: {min(all_rr):.1f} - {max(all_rr):.1f} ms")
            value = rmssd(all_rr)
            print(f"  RMSSD (HRV): {value} ms" if value else "  RMSSD: insufficient beats")
        print(f"  sensor contact detected: {any(s.get('sensor_contact') for s in samples)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))