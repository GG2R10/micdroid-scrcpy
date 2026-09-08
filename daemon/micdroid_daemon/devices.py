"""Known-device roster: devices the user has already `adb pair`-ed at least
once via terminal (v1 defers the pairing UI itself - see plan), persisted so
the plasmoid can list/reconnect them without re-pairing every session.

This is deliberately separate from the *live* adb device table: adb_tracker.py
re-derives live state (device/offline/unauthorized/absent) from
`host:track-devices` every run and merges it onto this roster in memory. Only
Pair-equivalent events (ConnectByAddress, Forget, last_seen updates) touch disk,
not every track-devices tick.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

DEVICES_DIR = Path.home() / ".config" / "micdroid"
DEVICES_FILE = DEVICES_DIR / "devices.json"


@dataclass
class Device:
    serial: str  # adb transport serial, e.g. "192.168.1.18:5555" or a USB serial
    name: str = ""
    transport: str = "tcpip"  # "tcpip" | "usb"
    last_address: str = ""  # "ip:port", empty for usb devices
    wifi_adb2_capable: bool = False
    last_paired: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)

    # --- live fields, never persisted, filled in by adb_tracker on each read ---
    live_state: str = "gone"  # device|offline|unauthorized|authorizing|no_permissions|gone
    forwarding_state: str = "Disconnected"

    def to_persisted_dict(self) -> dict:
        d = asdict(self)
        d.pop("live_state", None)
        d.pop("forwarding_state", None)
        return d


class DeviceRoster:
    def __init__(self) -> None:
        self._devices: dict[str, Device] = {}
        self.load()

    def load(self) -> None:
        if not DEVICES_FILE.exists():
            return
        try:
            raw = json.loads(DEVICES_FILE.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            log.warning("could not read %s: %s", DEVICES_FILE, exc)
            return
        for entry in raw.get("devices", []):
            try:
                dev = Device(**{k: v for k, v in entry.items() if k in Device.__dataclass_fields__})
            except TypeError as exc:
                log.warning("skipping malformed device entry %r: %s", entry, exc)
                continue
            self._devices[dev.serial] = dev

    def save(self) -> None:
        DEVICES_DIR.mkdir(parents=True, mode=0o700, exist_ok=True)
        payload = {"devices": [d.to_persisted_dict() for d in self._devices.values()]}
        tmp = DEVICES_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, indent=2))
        tmp.replace(DEVICES_FILE)

    def upsert(self, device: Device, persist: bool = True) -> None:
        self._devices[device.serial] = device
        if persist:
            self.save()

    def touch_seen(self, serial: str) -> None:
        """Cheap, frequent update - does NOT write to disk on every call.
        Callers should periodically call save() (e.g. on state transitions)
        rather than after every touch_seen to avoid disk churn on every
        track-devices tick.
        """
        dev = self._devices.get(serial)
        if dev is not None:
            dev.last_seen = time.time()

    def forget(self, serial: str) -> bool:
        if serial in self._devices:
            del self._devices[serial]
            self.save()
            return True
        return False

    def get(self, serial: str) -> Device | None:
        return self._devices.get(serial)

    def all(self) -> list[Device]:
        return list(self._devices.values())
