"""Unfiltered BLE diagnostic dump.

The service-filtered scan can miss the band: WHOOP advertises anonymously when
it is not connected, and Windows does not always surface service UUIDs in the
advertisement payload. This dumps every nearby device with full detail so the
band can be identified by name, manufacturer data, or signal strength.
"""

import argparse
import asyncio

from bleak import BleakScanner

from whoop.gatt import GEN4, GEN5


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=20.0)
    args = parser.parse_args()

    print(f"Unfiltered scan, {args.timeout:.0f}s. Listing strongest first.\n")
    devices = await BleakScanner.discover(timeout=args.timeout, return_adv=True)

    rows = sorted(devices.values(), key=lambda pair: pair[1].rssi, reverse=True)
    whoop_hits = []

    for device, adv in rows:
        uuids = [u.lower() for u in adv.service_uuids]
        is_whoop = any(
            u.startswith(GEN5.service[:8]) or u.startswith(GEN4.service[:8])
            for u in uuids
        )
        flag = "  <<< WHOOP SERVICE" if is_whoop else ""
        if is_whoop:
            whoop_hits.append((device, adv))

        print(f"{adv.rssi:>5} dBm  {device.address}  {device.name or '(anonymous)'}{flag}")
        if adv.service_uuids:
            print(f"         service_uuids: {adv.service_uuids}")
        if adv.manufacturer_data:
            for company, payload in adv.manufacturer_data.items():
                print(f"         manufacturer: id={company} (0x{company:04X}) data={payload.hex()}")
        if adv.service_data:
            for uuid, payload in adv.service_data.items():
                print(f"         service_data: {uuid} = {payload.hex()}")
        if adv.tx_power is not None:
            print(f"         tx_power: {adv.tx_power}")

    print(f"\n{len(rows)} devices total, {len(whoop_hits)} with a WHOOP service UUID.")
    if not whoop_hits:
        print("\nThe band is not advertising its WHOOP service to this machine.")
        print("Most likely cause: it is still connected to your phone. BLE is")
        print("one-central, so the strap will not advertise while the official")
        print("app (or any other central) holds the link.")
        print("\nTry, in order:")
        print("  1. Force-close the WHOOP app on your phone.")
        print("  2. Turn OFF Bluetooth on your phone entirely.")
        print("  3. Take the strap off the charger and put it on your wrist,")
        print("     or double-tap it to wake the radio.")
        print("  4. If it was ever paired to Windows, remove it from")
        print("     Settings > Bluetooth & devices, then re-run this scan.")
    return 0 if whoop_hits else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))