"""Per-device forwarding state machine.

States (Device.forwarding_state):
    Disconnected -> ConnectedIdle -> Forwarding <-> DegradedProbing -> Reconnecting -> NeedsRepair

Transition summary (see project plan for the full diagram):
  - track-devices reporting "device" for a Disconnected device -> ConnectedIdle,
    and (if autoStartOnKnownDevice and no other active session) auto-starts
    forwarding.
  - track-devices reporting anything else for the *actively forwarding* device
    goes straight to Reconnecting (track-devices already gave a definitive
    negative signal, no need for the probing step).
  - A failed liveness probe while Forwarding (track-devices still says
    "device" - the "Wi-Fi ADB lies" case) goes to DegradedProbing first; a
    second consecutive failure escalates to Reconnecting.
  - scrcpy exiting with code 2 (disconnected mid-session) goes straight to
    Reconnecting.
  - Reconnecting retries `adb connect` with exponential backoff
    (config.reconnectBackoffSec) up to config.maxReconnectAttempts, falling
    back to Avahi/mDNS IP re-resolution if the last-known address stops
    working; exhausting attempts lands in NeedsRepair (Doze can kill wireless
    adbd in a way nothing remote can revive - don't retry forever).

v1 constraint: only one device may be in Forwarding/DegradedProbing/
Reconnecting at a time (a single virtual-mic pair only needs one source).
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable

from . import adb_tracker, pipewire_route
from .config import Config
from .devices import Device, DeviceRoster
from .notify import notify
from .scrcpy_session import ScrcpyExit, ScrcpySession

log = logging.getLogger(__name__)

EmitSignal = Callable[..., Awaitable[None]]  # (signal_name, *args) -> None

ACTIVE_STATES = {"Forwarding", "DegradedProbing", "Reconnecting"}


class ForwardingStateMachine:
    def __init__(self, config: Config, roster: DeviceRoster, emit: EmitSignal) -> None:
        self._config = config
        self._roster = roster
        self._emit = emit

        self._active_serial: str | None = None
        self._session: ScrcpySession | None = None
        self._loopback: pipewire_route.OwnedLoopback | None = None
        self._probe_task: asyncio.Task | None = None
        self._routing_watch_task: asyncio.Task | None = None
        self._reconnect_task: asyncio.Task | None = None
        self._reconnect_attempt = 0
        self._last_dirty_save = 0.0
        # Whatever the system default source was right before we (optionally)
        # switched it to our virtual mic - restored on teardown so a stopped
        # session doesn't leave the OS pointing at a mic that may no longer
        # even exist. None means "we haven't touched it this session".
        self._previous_default_source: str | None = None

    @property
    def active_serial(self) -> str | None:
        return self._active_serial

    # --- helpers -----------------------------------------------------

    def _adb_path(self) -> str:
        return self._config.get("adbPath") or "adb"

    def _scrcpy_path(self) -> str:
        return self._config.get("scrcpyPath") or "scrcpy"

    async def _set_state(self, dev: Device, new_state: str) -> None:
        if dev.forwarding_state == new_state:
            return
        log.info("device %s: %s -> %s", dev.serial, dev.forwarding_state, new_state)
        dev.forwarding_state = new_state
        await self._emit("ForwardingStateChanged", dev.serial, new_state)

    def _has_other_active_session(self, serial: str) -> bool:
        return self._active_serial is not None and self._active_serial != serial

    # --- adb_tracker events -------------------------------------------

    async def on_adb_event(self, serial: str, adb_state: str) -> None:
        dev = self._roster.get(serial)
        if dev is None:
            if adb_state != "device":
                return  # don't bother auto-registering devices that aren't even up
            dev = await self._auto_register(serial)

        dev.live_state = adb_state
        self._roster.touch_seen(serial)
        await self._emit("DeviceStateChanged", serial, adb_state)

        if adb_state == "device":
            await self._on_device_reachable(dev)
        else:
            await self._on_device_unreachable(dev, adb_state)

    async def _auto_register(self, serial: str) -> Device:
        name = await self._probe_device_name(serial)
        dev = Device(serial=serial, name=name, transport="usb" if ":" not in serial else "tcpip",
                     last_address=serial if ":" in serial else "",
                     wifi_adb2_capable=adb_tracker.is_wifi_adb2_capable(self._adb_path()))
        self._roster.upsert(dev)
        await self._emit("DeviceAdded", device_to_dbus_dict(dev))
        return dev

    async def _probe_device_name(self, serial: str) -> str:
        try:
            proc = await asyncio.create_subprocess_exec(
                self._adb_path(), "-s", serial, "shell", "getprop", "ro.product.model",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
            name = stdout.decode(errors="replace").strip()
            return name or serial
        except (asyncio.TimeoutError, OSError):
            return serial

    async def _on_device_reachable(self, dev: Device) -> None:
        if dev.forwarding_state in ("Disconnected", "NeedsRepair"):
            # NeedsRepair -> ConnectedIdle: the device became reachable again
            # (user re-paired, tapped USB, or came back on a trusted Wi-Fi
            # network) - drop back to idle rather than resuming automatically,
            # so a device that needed manual intervention doesn't silently
            # start forwarding again without the user noticing it recovered.
            await self._set_state(dev, "ConnectedIdle")
            self._roster.save()
            if (self._config.get("autoStartOnKnownDevice")
                    and not self._has_other_active_session(dev.serial)
                    and self._active_serial is None):
                await self.start_forwarding(dev.serial)
        elif dev.forwarding_state == "Reconnecting" and dev.serial == self._active_serial:
            # track-devices confirms the link is back - resume forwarding.
            self._cancel_reconnect()
            await self._resume_after_reconnect(dev)
        elif dev.forwarding_state == "DegradedProbing" and dev.serial == self._active_serial:
            pass  # let the probe loop confirm recovery, don't flip-flop on track-devices alone

    async def _on_device_unreachable(self, dev: Device, adb_state: str) -> None:
        if dev.serial == self._active_serial and dev.forwarding_state in ("Forwarding", "DegradedProbing"):
            log.info("track-devices reports %s for actively-forwarding %s - reconnecting",
                      adb_state, dev.serial)
            await self._enter_reconnecting(dev)
        elif dev.forwarding_state == "ConnectedIdle":
            await self._set_state(dev, "Disconnected")
            self._roster.save()

    # --- D-Bus-facing commands -----------------------------------------

    async def start_forwarding(self, serial: str) -> tuple[bool, str]:
        dev = self._roster.get(serial)
        if dev is None:
            return False, f"unknown device {serial}"
        if self._has_other_active_session(serial):
            return False, f"another device ({self._active_serial}) is already forwarding"
        if dev.forwarding_state not in ("ConnectedIdle",):
            return False, f"device is {dev.forwarding_state}, expected ConnectedIdle"

        try:
            self._loopback = await pipewire_route.ensure_virtual_mic(
                self._config.get("virtualSinkName"), self._config.get("virtualSourceName"),
                self._config.get("virtualSinkDescription"), self._config.get("virtualSourceDescription"),
            )
        except RuntimeError as exc:
            await self._emit("ErrorOccurred", serial, "pipewire_setup_failed", str(exc))
            return False, str(exc)

        self._active_serial = serial
        self._session = ScrcpySession(
            self._scrcpy_path(), serial,
            self._config.get("audioSource"), self._config.get("audioCodec"),
            on_exit=self._on_scrcpy_exit,
        )
        try:
            await self._session.start()
        except OSError as exc:
            await self._emit("ErrorOccurred", serial, "scrcpy_spawn_failed", str(exc))
            self._active_serial = None
            return False, str(exc)

        routed = await pipewire_route.route_scrcpy_to_sink(self._config.get("virtualSinkName"))
        if not routed:
            await self._emit(
                "ErrorOccurred", serial, "routing_failed",
                "scrcpy's audio stream could not be moved to the virtual mic sink; "
                "audio may be playing on your default output instead",
            )
        else:
            # Keep re-applying the redirect for the rest of the session -
            # see pipewire_route.watch_scrcpy_routing's docstring: a one-shot
            # move alone doesn't survive the system's default sink changing
            # later (confirmed live 2026-09-10), since scrcpy's stream gets
            # torn down and recreated to follow the new default.
            self._routing_watch_task = asyncio.create_task(
                pipewire_route.watch_scrcpy_routing(self._config.get("virtualSinkName")),
                name=f"routing-watch-{serial}",
            )
        if routed and self._config.get("setAsDefaultSource"):
            # Capture whatever was default *before* switching, once per
            # session - if this fires again on a resume-after-reconnect (see
            # _resume_after_reconnect), self._previous_default_source is
            # already set from the original start, and we don't want to
            # overwrite it with our own virtual mic (which is what
            # get-default-source would now return).
            if self._previous_default_source is None:
                self._previous_default_source = await pipewire_route.get_default_source()
            await pipewire_route.set_default_source(self._config.get("virtualSourceName"))

        await self._set_state(dev, "Forwarding")
        self._reconnect_attempt = 0
        self._probe_task = asyncio.create_task(
            self._probe_loop(dev), name=f"probe-{serial}"
        )
        await notify(f"{dev.name} connected", "Reenviando micrófono a Virtual Microphone")
        return True, "forwarding started"

    async def stop_forwarding(self, serial: str) -> tuple[bool, str]:
        if serial != self._active_serial:
            return False, "device is not the active forwarding session"
        dev = self._roster.get(serial)
        await self._teardown_active_session()
        if dev is not None:
            await self._set_state(dev, "ConnectedIdle")
            await notify(f"{dev.name} disconnected", "Forwarding detenido")
        return True, "forwarding stopped"

    async def forget(self, serial: str) -> bool:
        if serial == self._active_serial:
            await self.stop_forwarding(serial)
        removed = self._roster.forget(serial)
        if removed:
            await self._emit("DeviceRemoved", serial)
        return removed

    async def rekey_device(self, old_serial: str, new_serial: str) -> None:
        """A tcpip device's ip:port changed (wireless debugging's connect
        port is ephemeral) but it's the same device we already know about -
        rename its roster entry in place and tell the widget via the same
        DeviceRemoved+DeviceAdded pair it already knows how to handle,
        rather than leaving a stale row plus a separately auto-registered
        duplicate under the new address.
        """
        if old_serial == new_serial or not self._roster.rekey(old_serial, new_serial):
            return
        if self._active_serial == old_serial:
            self._active_serial = new_serial
        dev = self._roster.get(new_serial)
        await self._emit("DeviceRemoved", old_serial)
        await self._emit("DeviceAdded", device_to_dbus_dict(dev))

    # --- internal: probing / reconnecting -------------------------------

    async def _probe_loop(self, dev: Device) -> None:
        interval = self._config.get("probeIntervalSec")
        consecutive_failures = 0
        try:
            while dev.serial == self._active_serial:
                await asyncio.sleep(interval)
                if dev.forwarding_state not in ("Forwarding", "DegradedProbing"):
                    return
                ok = await adb_tracker.liveness_probe(self._adb_path(), dev.serial)
                if ok:
                    consecutive_failures = 0
                    if dev.forwarding_state == "DegradedProbing":
                        await self._set_state(dev, "Forwarding")
                else:
                    consecutive_failures += 1
                    if consecutive_failures == 1:
                        await self._set_state(dev, "DegradedProbing")
                    else:
                        await self._enter_reconnecting(dev)
                        return
        except asyncio.CancelledError:
            return

    async def _on_scrcpy_exit(self, serial: str, kind: ScrcpyExit) -> None:
        dev = self._roster.get(serial)
        if dev is None or serial != self._active_serial:
            return
        if kind == ScrcpyExit.DISCONNECTED_MID_SESSION:
            await self._enter_reconnecting(dev)
        elif kind == ScrcpyExit.NEVER_CONNECTED:
            await self._emit("ErrorOccurred", serial, "scrcpy_never_connected",
                              "scrcpy could not establish the initial connection")
            await self._teardown_active_session()
            await self._set_state(dev, "ConnectedIdle")
        # NORMAL/UNKNOWN: nothing to do, stop_forwarding()/teardown already handled it

    async def _enter_reconnecting(self, dev: Device) -> None:
        if self._probe_task is not None:
            self._probe_task.cancel()
            self._probe_task = None
        if self._routing_watch_task is not None:
            # Otherwise start_forwarding() below (on a successful reconnect)
            # would spawn a second `pactl subscribe` watcher on top of this
            # one instead of replacing it - a leaked subprocess per
            # reconnect cycle, same shape of bug as the pre-existing
            # NeedsRepair leak this file's _release_forwarding_resources
            # comment already documents.
            self._routing_watch_task.cancel()
            self._routing_watch_task = None
        if self._session is not None:
            await self._session.stop()
            self._session = None
        # Keep the virtual mic sink/source alive across reconnect attempts so
        # nothing downstream (Discord, OBS...) sees the device disappear.
        await self._set_state(dev, "Reconnecting")
        self._reconnect_attempt = 0
        self._reconnect_task = asyncio.create_task(
            self._reconnect_loop(dev), name=f"reconnect-{dev.serial}"
        )

    def _cancel_reconnect(self) -> None:
        if self._reconnect_task is not None:
            self._reconnect_task.cancel()
            self._reconnect_task = None

    async def _reconnect_loop(self, dev: Device) -> None:
        backoff_schedule = self._config.get("reconnectBackoffSec")
        max_attempts = self._config.get("maxReconnectAttempts")
        adb_path = self._adb_path()
        try:
            while self._reconnect_attempt < max_attempts:
                delay = backoff_schedule[min(self._reconnect_attempt, len(backoff_schedule) - 1)]
                await asyncio.sleep(delay)
                self._reconnect_attempt += 1

                address = dev.last_address
                ok, message = (False, "no known address") if not address else \
                    await adb_tracker.adb_connect(adb_path, address)

                if not ok and not dev.wifi_adb2_capable:
                    candidates = await adb_tracker.resolve_ip_via_avahi()
                    for candidate in candidates:
                        ok, message = await adb_tracker.adb_connect(adb_path, candidate)
                        if ok:
                            dev.last_address = candidate
                            break

                if ok:
                    log.info("reconnected to %s on attempt %d", dev.serial, self._reconnect_attempt)
                    # track-devices will independently confirm "device" and
                    # call _on_device_reachable -> _resume_after_reconnect;
                    # this loop's job is done either way.
                    return
                log.info("reconnect attempt %d/%d for %s failed: %s",
                          self._reconnect_attempt, max_attempts, dev.serial, message)

            # Give up releasing the loopback and restoring the default
            # source too - previously this left both hanging around
            # forever (a pre-existing gap noticed while adding default
            # -source support: nothing ever reverted it once a device
            # gave up reconnecting), and also left active_serial pointing
            # at the dead device, permanently blocking starting forwarding
            # on any other one. Uses _release_forwarding_resources(), not
            # the full _teardown_active_session() - see that function's
            # docstring for why (this runs inside the reconnect task
            # itself).
            await self._release_forwarding_resources()
            await self._set_state(dev, "NeedsRepair")
            await self._emit(
                "ErrorOccurred", dev.serial, "reconnect_exhausted",
                "Could not reconnect after several attempts. The phone may need "
                "USB debugging re-enabled or a fresh `adb pair`.",
            )
            await notify(f"{dev.name}: reconnection failed",
                         "Puede que necesites re-emparejar o conectar por USB", urgency="critical")
        except asyncio.CancelledError:
            return

    async def _resume_after_reconnect(self, dev: Device) -> None:
        self._reconnect_task = None
        # Live bug, confirmed 2026-09-10: dev.forwarding_state is still
        # "Reconnecting" at this point (nothing transitions it back before
        # calling start_forwarding), and start_forwarding refuses to run
        # unless the device is "ConnectedIdle" - so every single resume was
        # failing with "device is Reconnecting, expected ConnectedIdle",
        # leaving the device stuck and never actually resuming audio.
        await self._set_state(dev, "ConnectedIdle")
        ok, message = await self.start_forwarding(dev.serial)
        if not ok:
            log.warning("could not resume forwarding for %s after reconnect: %s", dev.serial, message)

    async def _release_forwarding_resources(self) -> None:
        """The part of teardown that's safe to call from *inside* the
        reconnect loop itself (see the NeedsRepair path in
        _reconnect_loop): unlike _teardown_active_session, this never
        touches _reconnect_task, so it can't cancel the very task that's
        calling it (self._reconnect_task.cancel() marks the currently
        -running task for cancellation too, and the next `await` inside it -
        e.g. this same function's own loopback.stop() - would raise
        CancelledError right back into itself).
        """
        if self._routing_watch_task is not None:
            self._routing_watch_task.cancel()
            self._routing_watch_task = None
        if self._session is not None:
            await self._session.stop()
            self._session = None
        if self._loopback is not None:
            await self._loopback.stop()
            self._loopback = None
        if self._previous_default_source is not None:
            await pipewire_route.set_default_source(self._previous_default_source)
            self._previous_default_source = None
        self._active_serial = None

    async def _teardown_active_session(self) -> None:
        if self._probe_task is not None:
            self._probe_task.cancel()
            self._probe_task = None
        self._cancel_reconnect()
        await self._release_forwarding_resources()

    async def shutdown(self) -> None:
        """Called on daemon stop - don't leave scrcpy/pw-loopback orphaned."""
        await self._teardown_active_session()


def device_to_dbus_dict(dev: Device) -> dict:
    return {
        "serial": dev.serial,
        "name": dev.name,
        "transport": dev.transport,
        "address": dev.last_address,
        "state": dev.live_state,
        "wifiAdb2Capable": dev.wifi_adb2_capable,
        "forwardingState": dev.forwarding_state,
    }
