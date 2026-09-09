"""Daemon configuration: defaults, load/save to ~/.config/micdroid/config.json.

The plasmoid pushes its kcfg-backed settings to the daemon via the SetConfig
D-Bus method every time Plasmoid.configurationChanged fires. We persist the
merged result to disk so a daemon restart (systemd Restart=on-failure) picks
up the last known settings instead of resetting to defaults mid-session.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

CONFIG_DIR = Path.home() / ".config" / "micdroid"
CONFIG_FILE = CONFIG_DIR / "config.json"

DEFAULTS: dict[str, Any] = {
    # scrcpy audio options - see `scrcpy --list-audio-sources` / doc/audio.md
    "audioSource": "mic",
    "audioCodec": "raw",
    # PipeWire loopback node names. Default matches the user's own pre-existing
    # static loopback config so both can target the same virtual mic.
    "virtualSinkName": "VirtualMicSink",
    "virtualSourceName": "VirtualMicSource",
    # What apps actually display in their mic picker (node.description, not
    # node.name) - only takes effect on a pair this daemon creates itself,
    # never on a pre-existing sink/source it's just reusing (see
    # pipewire_route.ensure_virtual_mic's docstring - there's no pactl
    # command to rename an existing node's description). Empty string means
    # "just use the name above".
    "virtualSinkDescription": "",
    "virtualSourceDescription": "",
    # Opt-in, off by default - this changes the *system's* default
    # microphone, a side effect real enough (e.g. it could affect an
    # unrelated app that queries the default mid-session) that it shouldn't
    # happen without the user asking for it, same reasoning as
    # autoStartOnKnownDevice below.
    "setAsDefaultSource": False,
    # Product decision: single global toggle, no per-device "primary" concept.
    "autoStartOnKnownDevice": False,
    # Reconnection state machine tuning (see state_machine.py).
    "probeIntervalSec": 15,
    "maxReconnectAttempts": 5,
    "reconnectBackoffSec": [2, 5, 10, 20, 40, 60],
    # Optional overrides; empty string means "resolve via PATH".
    "adbPath": "",
    "scrcpyPath": "",
}


class Config:
    """In-memory config, backed by a JSON file. Not thread-safe; only touched
    from the daemon's single asyncio event loop thread.
    """

    def __init__(self) -> None:
        self._values: dict[str, Any] = dict(DEFAULTS)
        self.load()

    def load(self) -> None:
        if not CONFIG_FILE.exists():
            return
        try:
            on_disk = json.loads(CONFIG_FILE.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            log.warning("could not read %s, using defaults: %s", CONFIG_FILE, exc)
            return
        for key in DEFAULTS:
            if key in on_disk:
                self._values[key] = on_disk[key]

    def save(self) -> None:
        CONFIG_DIR.mkdir(parents=True, mode=0o700, exist_ok=True)
        tmp = CONFIG_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(self._values, indent=2))
        tmp.replace(CONFIG_FILE)

    def update(self, partial: dict[str, Any]) -> None:
        """Merge a partial config dict (only known keys) and persist it."""
        changed = False
        for key, value in partial.items():
            if key not in DEFAULTS:
                log.debug("ignoring unknown config key %r", key)
                continue
            if self._values.get(key) != value:
                self._values[key] = value
                changed = True
        if changed:
            self.save()

    def __getitem__(self, key: str) -> Any:
        return self._values[key]

    def get(self, key: str, default: Any = None) -> Any:
        return self._values.get(key, default)

    def as_dict(self) -> dict[str, Any]:
        return dict(self._values)
