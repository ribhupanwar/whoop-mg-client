"""Service-filtered BLE scan for a WHOOP band.

A passive scan hides the service UUID and the band advertises anonymously, so
the filter is required, not an optimization.

BLE is one-central: the official WHOOP app must be disconnected or the band
will not advertise to this machine.
"""

import argparse
import asyncio

from bleak import BleakScanner
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData

from whoop.gatt import GEN4, GEN5, profile_for_service

TARGET_UUIDS = [GEN5.service, GEN4.service]


async def scan(timeout: float) -> list[tuple[BLEDevice, AdvertisementData]]:
    found = await BleakScanner.discover(
        timeout=timeout,
        service_uuids=TARGET_UUIDS,
        return_adv=True,
    )
    return list(found.values())


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args()

    print(f"Scanning {args.timeout:.0f}s for WHOOP service UUIDs:")
    for uuid in TARGET_UUIDS:
        print(f"  {uuid}")
    print("If nothing appears: enable Bluetooth, close the WHOOP app,")
    print("and disconnect the strap from your phone.\n")

    try:
        results = await scan(args.timeout)
    except Exception as exc:
        print(f"Scan failed: {type(exc).__name__}: {exc}")
        return 1

    if not results:
        print("No WHOOP band found.")
        return 1

    for device, adv in results:
        matched = next(
            (u for u in adv.service_uuids if profile_for_service(u)), None
        )
        gen = "gen5 (WHOOP 5.0 / MG)" if matched and matched.startswith("fd4b") else "gen4 (WHOOP 4.0)"
        print(f"FOUND  {device.address}  rssi={adv.rssi}  {gen}")
        print(f"       name={device.name or '(anonymous)'}")
        print(f"       uuids={adv.service_uuids}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
