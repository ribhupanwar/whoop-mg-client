"""GATT service and characteristic UUIDs per WHOOP generation.

The low nibble is shared across generations; only the prefix differs.
Gen5 covers WHOOP 5.0 and MG, which use one wire format.
"""

from dataclasses import dataclass

SOF = 0xAA


@dataclass(frozen=True)
class GattProfile:
    service: str
    cmd_to: str
    cmd_from: str
    events: str
    data: str
    memfault: str

    @property
    def notifiable(self) -> tuple[str, ...]:
        return (self.cmd_from, self.events, self.data, self.memfault)


def _family(prefix: str, suffix: str) -> GattProfile:
    def u(nibble: int) -> str:
        return f"{prefix}000{nibble}-{suffix}"

    return GattProfile(
        service=u(1),
        cmd_to=u(2),
        cmd_from=u(3),
        events=u(4),
        data=u(5),
        memfault=u(7),
    )


GEN4 = _family("6108", "8d6d-82b8-614a-1c8cb0f8dcc6")
GEN5 = _family("fd4b", "cce1-4033-93ce-002d5875f58a")

PROFILES = {"gen4": GEN4, "gen5": GEN5}

# Standard SIG services, readable without any proprietary handshake.
DEVICE_INFO_SERVICE = "0000180a-0000-1000-8000-00805f9b34fb"
BATTERY_SERVICE = "0000180f-0000-1000-8000-00805f9b34fb"
HEART_RATE_SERVICE = "0000180d-0000-1000-8000-00805f9b34fb"


def profile_for_service(uuid: str) -> GattProfile | None:
    """Identify generation from an advertised service UUID."""
    lowered = uuid.lower()
    for profile in PROFILES.values():
        if lowered.startswith(profile.service[:8]):
            return profile
    return None