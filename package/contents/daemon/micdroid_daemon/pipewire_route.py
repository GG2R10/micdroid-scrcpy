"""PipeWire routing: get scrcpy's audio stream into a virtual-mic sink/source
pair, and make sure that pair exists in the first place.

Design confirmed by live testing against the user's actual PipeWire setup
(see project plan's "Spikes" section) rather than assumed from docs:

  - `PULSE_SINK` / `SDL_AUDIODRIVER=pulse` env vars do NOT redirect scrcpy's
    stream: scrcpy 4.x links against SDL 3.x, whose PipeWire backend connects
    with an explicit `target.object` pointing at the system default sink,
    ignoring those env vars entirely (confirmed via `pactl list sink-inputs`
    while scrcpy was running).
  - What DOES work reliably: scrcpy's stream is trivially identifiable by
    `node.name == "scrcpy"` (and `application.name == "scrcpy"`), and a single
    `pactl move-sink-input <id> <sink>` right after it appears redirects it
    instantly and stays put for the life of the stream. No continuous event
    listener is needed for this - just a short bounded retry loop right after
    spawning scrcpy.
  - The user's own system already has a static `VirtualMicSink`/
    `VirtualMicSource` loopback (defined in their pipewire.conf.d for
    AudioRelay) present at all times, independent of whether AudioRelay is
    running. So "ensure the sink exists" must check first and only spawn our
    own `pw-loopback` as a fallback, to avoid a node-name collision with the
    user's static config and to interoperate with it by default.
"""

from __future__ import annotations

import asyncio
import logging

log = logging.getLogger(__name__)

# scrcpy's audio node can take several seconds to appear on a cold start
# (pushing scrcpy-server to the device, encoder/codec init) - empirically
# observed up to ~4-5s even on a fast LAN, so budget generously (10s total)
# rather than tightly, since this is a one-time check right after spawn, not
# a recurring poll.
MOVE_RETRY_ATTEMPTS = 20
MOVE_RETRY_INTERVAL = 0.5  # seconds


async def _pactl_list_short_sinks() -> list[str]:
    proc = await asyncio.create_subprocess_exec(
        "pactl", "list", "short", "sinks",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await proc.communicate()
    names = []
    for line in stdout.decode(errors="replace").splitlines():
        fields = line.split("\t")
        if len(fields) >= 2:
            names.append(fields[1])
    return names


async def sink_exists(name: str) -> bool:
    return name in await _pactl_list_short_sinks()


class OwnedLoopback:
    """Wraps a `pw-loopback` subprocess we spawned ourselves. Killing it tears
    the module (and its sink+source pair) down instantly - nothing is written
    to disk, unlike the user's static pipewire.conf.d equivalent.
    """

    def __init__(self, process: asyncio.subprocess.Process) -> None:
        self._process = process

    async def stop(self) -> None:
        if self._process.returncode is not None:
            return
        self._process.terminate()
        try:
            await asyncio.wait_for(self._process.wait(), timeout=3.0)
        except asyncio.TimeoutError:
            self._process.kill()
            await self._process.wait()


async def ensure_virtual_mic(sink_name: str, source_name: str,
                              sink_description: str = "", source_description: str = "") -> OwnedLoopback | None:
    """Returns an OwnedLoopback if we spawned our own pair (caller must stop()
    it when the forwarding session ends), or None if a sink with that name
    already existed (e.g. the user's static config) and nothing needs cleanup.

    The description args (what apps like Discord actually display in their
    microphone picker - `node.name` is just the internal identifier) only
    take effect on the pair *we* create here. There is no `pactl` command to
    rename an existing node's description after the fact (confirmed - it's
    not in `pactl --help`'s command list), so if a sink with this name
    already exists - e.g. a static pipewire.conf.d loopback set up before
    this project existed - its description is whatever that static config
    already gave it, unaffected by these settings.
    """
    if await sink_exists(sink_name):
        log.info("reusing existing PipeWire sink %r (its description, if any, is unchanged - "
                 "there's no way to rename an existing node's description)", sink_name)
        return None

    sink_description = sink_description or sink_name
    source_description = source_description or source_name
    log.info("spawning pw-loopback to create %r / %r", sink_name, source_name)
    process = await asyncio.create_subprocess_exec(
        "pw-loopback",
        "--capture-props",
        f"node.name={sink_name} node.description=\"{sink_description}\" "
        f"media.class=Audio/Sink audio.position=[FL,FR]",
        "--playback-props",
        f"node.name={source_name} node.description=\"{source_description}\" "
        f"media.class=Audio/Source audio.position=[FL,FR]",
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE,
    )
    # Give it a moment to actually register the nodes before we report success.
    for _ in range(10):
        if await sink_exists(sink_name):
            return OwnedLoopback(process)
        if process.returncode is not None:
            stderr = await process.stderr.read() if process.stderr else b""
            raise RuntimeError(f"pw-loopback exited early: {stderr.decode(errors='replace')}")
        await asyncio.sleep(0.3)
    raise RuntimeError(f"pw-loopback did not create sink {sink_name!r} in time")


async def _find_scrcpy_sink_input() -> str | None:
    proc = await asyncio.create_subprocess_exec(
        "pactl", "list", "sink-inputs",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await proc.communicate()
    text = stdout.decode(errors="replace")
    current_id: str | None = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("Sink Input #"):
            current_id = line.removeprefix("Sink Input #")
        elif line.startswith('node.name = "scrcpy"') and current_id is not None:
            return current_id
    return None


async def route_scrcpy_to_sink(sink_name: str) -> bool:
    """Bounded retry loop (not a continuous listener) that finds scrcpy's
    freshly-spawned sink-input and moves it to `sink_name` exactly once.
    Returns True if the move happened, False if scrcpy's stream never showed
    up within the retry budget (caller should surface this as an error - audio
    is still playing on the default device in that case, not silently lost).
    """
    for attempt in range(MOVE_RETRY_ATTEMPTS):
        sink_input_id = await _find_scrcpy_sink_input()
        if sink_input_id is not None:
            proc = await asyncio.create_subprocess_exec(
                "pactl", "move-sink-input", sink_input_id, sink_name,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode == 0:
                log.info("routed scrcpy sink-input %s -> %s", sink_input_id, sink_name)
                return True
            log.warning("pactl move-sink-input failed: %s", stderr.decode(errors="replace"))
            return False
        await asyncio.sleep(MOVE_RETRY_INTERVAL)
    log.warning("scrcpy audio stream did not appear within %.1fs",
                MOVE_RETRY_ATTEMPTS * MOVE_RETRY_INTERVAL)
    return False


# --- mute -----------------------------------------------------------
#
# Muting is applied to the virtual *source* (the end other apps - Discord,
# OBS, a browser tab - actually read as "the microphone"), not the sink
# scrcpy writes into. That keeps it a pure downstream toggle: scrcpy, the
# adb connection, and the loopback routing are all completely undisturbed -
# no subprocess spawn/kill, no re-routing, just PipeWire's own mute flag on
# one node. `pactl get/set-source-mute` output is confirmed live as
# "Mute: yes"/"Mute: no" text (pactl 17.x here), not a bare "yes"/"no" or a
# 1/0 flag, so parsing has to match that.

async def get_mute(source_name: str) -> bool | None:
    """Returns None if the source doesn't currently exist (e.g. no
    forwarding session has ever run yet) rather than raising - the caller
    should treat that as "nothing to mute", not an error.
    """
    proc = await asyncio.create_subprocess_exec(
        "pactl", "get-source-mute", source_name,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await proc.communicate()
    if proc.returncode != 0:
        return None
    return stdout.decode(errors="replace").strip().lower() == "mute: yes"


async def set_mute(source_name: str, muted: bool) -> bool:
    """Returns True if the mute state was actually applied, False if the
    source doesn't exist right now.
    """
    proc = await asyncio.create_subprocess_exec(
        "pactl", "set-source-mute", source_name, "1" if muted else "0",
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    if proc.returncode != 0:
        log.warning("pactl set-source-mute failed: %s", stderr.decode(errors="replace"))
        return False
    return True


async def toggle_mute(source_name: str) -> bool | None:
    """Returns the new mute state, or None if the source doesn't exist."""
    current = await get_mute(source_name)
    if current is None:
        return None
    ok = await set_mute(source_name, not current)
    return (not current) if ok else current


# --- default source (opt-in "make it the system mic" convenience) -------

async def get_default_source() -> str | None:
    proc = await asyncio.create_subprocess_exec(
        "pactl", "get-default-source",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await proc.communicate()
    if proc.returncode != 0:
        return None
    return stdout.decode(errors="replace").strip() or None


async def set_default_source(source_name: str) -> bool:
    proc = await asyncio.create_subprocess_exec(
        "pactl", "set-default-source", source_name,
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    if proc.returncode != 0:
        log.warning("pactl set-default-source failed: %s", stderr.decode(errors="replace"))
        return False
    return True
