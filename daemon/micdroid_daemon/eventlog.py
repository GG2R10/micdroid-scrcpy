"""Append-only runtime event log the plasmoid tails for live updates.

Why this exists instead of the plasmoid running `gdbus monitor` directly:
`gdbus monitor | head -n1` (the self-re-arming "block for one line, exit,
reconnect" idiom `gamemode-status` uses for its own state file) would work,
but `gdbus monitor` prints two banner lines before any real event on every
fresh invocation ("Monitoring signals on object ..." / "The name ... is owned
by ..."), and tearing the whole monitor subscription down and recreating it
for every single event risks losing any signal that fires in the gap between
disconnecting and resubscribing - D-Bus does not queue signals for a
subscriber that isn't currently connected.

Instead, since we own the daemon writing the signals in the first place, it
also appends one JSON line per event to this file. The plasmoid just
`tail -F`s it (exact same idiom as gamemode-status's state file), which is
gap-free: nothing needs to resubscribe to anything, the file position is all
that's tracked. The real D-Bus signals (dbus_service.py) still fire as well,
for any other consumer/`gdbus monitor` debugging - this file is purely an
implementation detail of how the plasmoid gets live updates cheaply.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/micdroid-{os.getuid()}")) / "micdroid"
EVENTS_FILE = RUNTIME_DIR / "events.log"


def init() -> None:
    RUNTIME_DIR.mkdir(parents=True, mode=0o700, exist_ok=True)
    # Truncate on daemon start - a stale line from a previous run pointing at
    # devices that may no longer be around isn't useful, and armCurrent()
    # (a direct ListDevices/GetStatus call) already covers the initial state.
    EVENTS_FILE.write_text("")


def append(signal_name: str, args: tuple) -> None:
    line = json.dumps({"signal": signal_name, "args": list(args)})
    with EVENTS_FILE.open("a") as f:
        f.write(line + "\n")
