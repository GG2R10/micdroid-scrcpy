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
    instantly.
  - That redirect does NOT stay put for the life of the stream, though
    (confirmed live 2026-09-10, contradicting what this comment used to
    claim): SDL's PipeWire backend keeps following the system's default sink
    even after being moved, and if the *default* changes for any reason
    (KDE's audio applet, `wpctl set-default`, unplugging a device...) it
    destroys the existing stream and creates a brand new one - new node id,
    new client id, confirmed via `pactl subscribe` showing a `remove` and a
    fresh `new` sink-input event - which of course targets the new default,
    silently undoing our move. A one-shot move-after-spawn genuinely cannot
    survive this, since there is no stable node to keep a pin on; the fix is
    `watch_scrcpy_routing()` below, a small `pactl subscribe` loop kept
    running for the life of the forwarding session that re-applies the move
    every time scrcpy's stream reappears.
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
    """Returns the highest-numbered ("newest") sink-input id whose
    `node.name` is "scrcpy", or None if there isn't one right now.

    Newest, not first-seen: confirmed live 2026-09-10 that under rapid
    successive default-sink changes, SDL doesn't always tear down the
    previous generation of scrcpy's stream before the next one is already
    up - so briefly, more than one "scrcpy"-named sink-input can exist at
    once, an old one that's about to disappear and a new one that's
    actually carrying live audio right now. Sink-input ids are PipeWire
    object serials, which only ever increase for the life of the server, so
    the highest id among matches is always the most recently created one -
    picking the first match in listing order instead (the previous
    behaviour) could "fix" the dying stream while leaving the live one
    stuck on the wrong sink, which is exactly what was observed: a
    move that logged success while the audibly-wrong stream stayed put.
    """
    proc = await asyncio.create_subprocess_exec(
        "pactl", "list", "sink-inputs",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await proc.communicate()
    text = stdout.decode(errors="replace")
    current_id: str | None = None
    newest_id: str | None = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("Sink Input #"):
            current_id = line.removeprefix("Sink Input #")
        elif line.startswith('node.name = "scrcpy"') and current_id is not None:
            if newest_id is None or int(current_id) > int(newest_id):
                newest_id = current_id
    return newest_id


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


async def watch_scrcpy_routing(sink_name: str) -> None:
    """Runs for the whole life of a forwarding session (cancel this task on
    teardown) re-applying the scrcpy -> sink_name redirect every time it's
    needed, instead of the one-shot move `route_scrcpy_to_sink` does at
    startup.

    Why this exists: see the module docstring's 2026-09-10 update. In short,
    changing the system's default sink (e.g. from KDE's own audio applet)
    makes SDL tear down and recreate scrcpy's PipeWire stream to follow the
    new default, which produces a `new` sink-input event on `pactl subscribe`
    - so we just listen for that and re-move it, cheaply, for as long as
    forwarding is active.

    Confirmed live: `pactl subscribe`'s stdout is fully block-buffered (not
    line-buffered) once it's a pipe rather than a tty, like most libc-stdio
    programs - piping it straight into `asyncio.subprocess.PIPE` and doing
    `readline()` measured real events arriving up to ~50s late, batched
    behind unrelated PipeWire traffic (other apps' sink-inputs/clients
    churning) until the OS pipe buffer happened to fill or the process
    exited. `stdbuf -oL` forces line-buffering on that stdout and brought
    delivery back down to sub-second, matching a direct `pactl subscribe` on
    a terminal.

    That fixed *latency per event*, but not *throughput under a burst* -
    confirmed live 2026-09-10 with a second, worse bug: a single default-sink
    change doesn't just recreate scrcpy's stream, it makes *every* client
    (Firefox, Steam, the user's own AudioRelay loopback...) reconnect too,
    producing a burst of 10-20+ `new`/`change`/`remove` events all at once.
    The read loop used to `await` a whole find-with-retries-then-move cycle
    per event, serially - so a burst backed up the pending events in the
    pipe, and a correction that should've taken ~1s instead landed 46s
    later in one measured case (and, in a worse case with more concurrent
    reconnects than retry budget, effectively never - matching exactly what
    the user reported: scrcpy stuck audibly on the new default with no
    automatic recovery). Splitting the read loop from the actual
    find+move work below fixes this: the loop never blocks on subprocess
    work, so it drains the whole burst instantly, and a separate worker
    coalesces however many "something changed" signals piled up into a
    single fresh check once it's free.
    """
    proc = await asyncio.create_subprocess_exec(
        "stdbuf", "-oL", "pactl", "subscribe",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    log.info("routing watcher started (pid %s) for sink %r", proc.pid, sink_name)

    needs_check = asyncio.Event()

    async def _worker() -> None:
        while True:
            await needs_check.wait()
            needs_check.clear()
            try:
                # Retry, not a single shot: confirmed live 2026-09-10 that
                # `pactl list sink-inputs` run immediately after an event
                # can still race the object not being listable yet. If
                # more `needs_check` signals arrive *while* this is
                # running, they're not lost - the Event is already set
                # again by the time we loop back to `.wait()`, so we just
                # run one more fresh check right away instead of once per
                # signal (that per-signal serial approach is what caused
                # the 46s-late correction above).
                sink_input_id = None
                for _attempt in range(6):
                    sink_input_id = await _find_scrcpy_sink_input()
                    if sink_input_id is not None:
                        break
                    await asyncio.sleep(0.2)
                if sink_input_id is None:
                    log.warning("routing watcher saw activity but never found scrcpy's "
                                "stream to re-route (gave up after 6 attempts / ~1.2s)")
                    continue
                move = await asyncio.create_subprocess_exec(
                    "pactl", "move-sink-input", sink_input_id, sink_name,
                    stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE,
                )
                _, stderr = await move.communicate()
                if move.returncode == 0:
                    log.info("re-routed scrcpy sink-input %s -> %s (it followed a default-sink change)",
                              sink_input_id, sink_name)
                else:
                    log.warning("re-route after default-sink change failed: %s",
                                stderr.decode(errors="replace"))
            except asyncio.CancelledError:
                raise
            except Exception:
                # Never let one bad iteration kill the worker for the rest
                # of the session - log it and keep waiting for the next
                # signal instead of silently stopping (which, before this,
                # could only be noticed by reading the log for the
                # *absence* of further activity).
                log.exception("routing watcher's worker hit an unexpected error - "
                               "still listening for the next event")

    worker_task = asyncio.create_task(_worker(), name="routing-watch-worker")
    try:
        assert proc.stdout is not None
        while True:
            line = await proc.stdout.readline()
            if not line:
                # pactl subscribe's stdout closed on its own - shouldn't
                # happen while forwarding is active. Logged at WARNING
                # (not silently falling out of the loop) specifically
                # because a silent exit here is what would look like "the
                # watcher stopped working" with nothing in the log to show
                # why - confirmed live 2026-09-10 that without this, a dead
                # watcher left no trace at all.
                log.warning("routing watcher's pactl subscribe (pid %s) closed its "
                            "output - watcher exiting, no more auto-reroutes for "
                            "this session", proc.pid)
                break
            text = line.decode(errors="replace")
            # Only 'new' events matter here: that's the signature of SDL
            # recreating the stream (confirmed live - a default-sink change
            # produces exactly one 'new' plus a later 'remove', not a
            # 'change'). Reacting to every 'change' too would just mean
            # redundant no-op moves, but there's no need for the noise.
            # This check is deliberately cheap (a couple of substring
            # tests, no subprocess) - all the actual work happens in
            # _worker(), off this hot loop.
            if "'new'" in text and "sink-input" in text:
                needs_check.set()
    except asyncio.CancelledError:
        pass
    finally:
        worker_task.cancel()
        try:
            await worker_task
        except asyncio.CancelledError:
            pass
        log.info("routing watcher stopped (pid %s)", proc.pid)
        if proc.returncode is None:
            proc.terminate()
            try:
                await asyncio.wait_for(proc.wait(), timeout=2.0)
            except asyncio.TimeoutError:
                proc.kill()
                await proc.wait()


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
