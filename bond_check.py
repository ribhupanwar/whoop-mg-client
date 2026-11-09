"""Determine why the proprietary fd4b notifications cannot be subscribed.

Distinguishes an authentication/encryption requirement (needs a bond) from an
application-layer handshake requirement. Non-destructive: only reads and
subscription attempts, no commands written to the strap.
"""

import argparse
import asyncio

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError

from whoop.gatt import GEN5

CCCD = "00002902-0000-1000-8000-00805f9b34fb"


async def find_band(timeout: float) -> str:
    devices = await BleakScanner.discover(timeout=timeout, return_adv=True)
    for dev, _adv in devices.values():
        if "whoop" in (dev.name or "").lower():
            return dev.address
    raise RuntimeError("No WHOOP band found. Turn Bluetooth OFF on your phone.")


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address")
    parser.add_argument("--scan-timeout", type=float, default=15.0)
    args = parser.parse_args()

    address = args.address or await find_band(args.scan_timeout)
    print(f"Connecting to {address} ...\n")

    async with BleakClient(address, timeout=30.0) as client:
        print(f"Connected. MTU={client.mtu_size}")
        print(f"bleak reports services resolved: {client.services is not None}\n")

        for uuid in (GEN5.cmd_from, GEN5.events, GEN5.data):
            print(f"--- {uuid} ---")
            char = client.services.get_characteristic(uuid)
            if char is None:
                print("  characteristic not found\n")
                continue
            print(f"  properties: {char.properties}")

            for descriptor in char.descriptors:
                print(f"  descriptor: {descriptor.uuid}")
                if descriptor.uuid.lower() == CCCD:
                    try:
                        value = await client.read_gatt_descriptor(descriptor.handle)
                        print(f"    CCCD read OK: {bytes(value).hex()}")
                    except Exception as exc:
                        print(f"    CCCD read FAILED: {type(exc).__name__}: {exc}")

            try:
                await client.start_notify(uuid, lambda _c, _d: None)
                print("  start_notify: SUCCESS")
                await client.stop_notify(uuid)
            except Exception as exc:
                print(f"  start_notify FAILED: {type(exc).__name__}")
                print(f"    message: {exc}")
                print(f"    args: {exc.args!r}")
                if isinstance(exc, BleakError):
                    print(f"    bleak error detail: {getattr(exc, 'error_code', 'n/a')}")
            print()

        write_char = client.services.get_characteristic(GEN5.cmd_to)
        if write_char:
            print(f"--- write characteristic {GEN5.cmd_to} ---")
            print(f"  properties: {write_char.properties}")
            print("  (no command written - this probe is read-only)")

    print("\nInterpretation:")
    print("  'Insufficient Authentication' / 'Insufficient Encryption' / GATT")
    print("  protocol error on CCCD write => the link must be BONDED first.")
    print("  Pair the strap in Windows Settings > Bluetooth & devices > Add device,")
    print("  then re-run probe.py over the bonded link.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
