"""The D-Bus service the plasmoid talks to.

Bus name: org.micdroid.Daemon1
Object path: /org/micdroid/Daemon
Interface: org.micdroid.Daemon1

Built on `dbus-next` (asyncio-native, pure Python - no compiled extension,
unlike `sdbus`/`python-dbus`'s GLib mainloop bridge) so the same event loop
drives D-Bus, the adb track-devices socket, and subprocess supervision.

The plasmoid drives this exactly like it would any other D-Bus service (see
../../package/contents/code/daemonctl.sh): `gdbus call` for methods,
`gdbus monitor` for signals.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from dbus_next import BusType, Variant
from dbus_next.aio import MessageBus
from dbus_next.service import PropertyAccess, ServiceInterface, dbus_property, method, signal

from . import deps
from .config import Config
from .devices import Device, DeviceRoster
from .state_machine import ForwardingStateMachine, device_to_dbus_dict

log = logging.getLogger(__name__)

BUS_NAME = "org.micdroid.Daemon1"
OBJECT_PATH = "/org/micdroid/Daemon"
INTERFACE_NAME = "org.micdroid.Daemon1"


def _variant(value: Any) -> Variant:
    if isinstance(value, bool):
        return Variant("b", value)
    if isinstance(value, int):
        return Variant("x", value)
    if isinstance(value, float):
        return Variant("d", value)
    if isinstance(value, str):
        return Variant("s", value)
    if isinstance(value, list):
        if all(isinstance(v, str) for v in value):
            return Variant("as", value)
        if all(isinstance(v, int) for v in value):
            return Variant("ai", value)
    if value is None:
        return Variant("s", "")
    return Variant("s", str(value))


def _to_variant_dict(d: dict[str, Any]) -> dict[str, Variant]:
    # Keep keys with a None value (e.g. a missing dependency) as an empty
    # string rather than dropping them - "checked, not found" must stay
    # distinguishable from "never checked" on the QML side.
    return {k: _variant(v) for k, v in d.items()}


class DaemonInterface(ServiceInterface):
    def __init__(self, config: Config, roster: DeviceRoster,
                 state_machine: ForwardingStateMachine) -> None:
        super().__init__(INTERFACE_NAME)
        self._config = config
        self._roster = roster
        self._sm = state_machine
        self._dependency_results: dict[str, str | None] = {}

    def set_dependency_results(self, results: dict[str, str | None]) -> None:
        self._dependency_results = results

    # --- methods ---------------------------------------------------
    #
    # ListDevices/GetStatus/RescanDependencies return a JSON-encoded string
    # ("s") rather than a native a{sv}/aa{sv} container. This is deliberate:
    # the plasmoid calls these through `gdbus call` from a shell DataSource,
    # and gdbus's GVariant text-format output for nested dict/array
    # containers is painful to parse reliably in QML/JS, whereas a single
    # quoted JSON string is one regex-strip + JSON.parse away. `gdbus monitor`
    # and any other real D-Bus client can still call these normally - they
    # just get a string back instead of a typed container.

    @method()
    def ListDevices(self) -> "s":  # noqa: N802 - D-Bus method naming convention
        return json.dumps([device_to_dbus_dict(d) for d in self._roster.all()])

    @method()
    def GetStatus(self) -> "s":
        active = self._sm.active_serial
        return json.dumps({
            "dependenciesOk": deps.all_required_ok(self._dependency_results),
            "dependencyResults": self._dependency_results,
            "activeDevice": active or "",
            "forwardingState": (
                self._roster.get(active).forwarding_state if active else "Disconnected"
            ),
        })

    def _register_connected_device(self, address: str, adb_path: str) -> str:
        """Upserts a roster entry for a device we just successfully
        `adb connect`ed to. The connect address IS the adb serial for tcpip
        devices, so it doubles as the device id.
        """
        from . import adb_tracker
        serial = address
        dev = self._roster.get(serial) or Device(serial=serial, name=serial,
                                                   transport="tcpip", last_address=address)
        dev.last_address = address
        dev.wifi_adb2_capable = adb_tracker.is_wifi_adb2_capable(adb_path)
        self._roster.upsert(dev)
        return serial

    @method()
    async def ConnectByAddress(self, address: "s") -> "bss":  # noqa: N802
        from . import adb_tracker
        adb_path = self._config.get("adbPath") or "adb"
        ok, message = await adb_tracker.adb_connect(adb_path, address)
        if not ok:
            return [False, message, ""]
        serial = self._register_connected_device(address, adb_path)
        return [True, message, serial]

    @method()
    async def Pair(self, host: "s", pair_port: "s", code: "s") -> "bbss":  # noqa: N802
        """Runs `adb pair`, then tries to auto-discover the (separate)
        connect port via mDNS and finish connecting in one step. If that
        discovery fails - Avahi not installed, or the phone just isn't
        advertising it - pairing has still succeeded; the widget should tell
        the user to finish with "Connect by address" using the IP:port shown
        on the phone's Wireless debugging screen.
        """
        from . import adb_tracker
        adb_path = self._config.get("adbPath") or "adb"
        paired, message = await adb_tracker.adb_pair(adb_path, f"{host}:{pair_port}", code)
        if not paired:
            return [False, False, message, ""]

        connected, address = await adb_tracker.find_and_connect_after_pairing(adb_path, host)
        if not connected:
            return [True, False,
                    "Paired successfully, but couldn't auto-discover the connect port. "
                    "Use \"Connect by address\" with the IP:port shown on the phone's "
                    "Wireless debugging screen.", ""]

        serial = self._register_connected_device(address, adb_path)
        return [True, True, f"Paired and connected as {address}", serial]

    @method()
    async def Connect(self, serial: "s") -> "bs":  # noqa: N802
        from .notify import notify

        dev = self._roster.get(serial)
        if dev is None:
            return [False, "unknown device"]

        # A USB device has no network address to (re)connect to at all -
        # adb's own notion of "connect" is a wireless-only operation. Without
        # this check, this would fall through to `adb connect <usb-serial>`,
        # a nonsensical call to a bare serial with no host:port in it, and
        # come back with some unhelpful adb parse error instead of a message
        # that actually tells the user what to do (confirmed as a real,
        # not hypothetical, case: the panel's own moto_g14 row hitting
        # exactly this when the cable's unplugged).
        if dev.transport == "usb":
            message = f"{dev.name} is connected over USB - plug the cable back in, there's no network address to reconnect to"
            await notify(f"{dev.name}: can't reconnect", message, urgency="critical")
            return [False, message]

        from . import adb_tracker

        adb_path = self._config.get("adbPath") or "adb"
        address = dev.last_address or serial
        ok, message = await adb_tracker.adb_connect(adb_path, address)
        if ok:
            await notify(f"{dev.name} reconnected", address)
            return [True, message]

        # Wireless debugging's connect port is ephemeral - confirmed live
        # this is a real, common failure mode, not hypothetical: toggling
        # "Wireless debugging" off/on (or just enough time passing) gives
        # the phone a *new* connect port, so a direct connect to the last
        # known address eventually starts failing with "Connection refused"
        # even though the device is genuinely still on the network and
        # still paired. Fall back to the same mDNS rediscovery the Pair
        # flow uses (scoped to this device's host) before giving up.
        #
        # Note this is still scoped to the *same host* (IP) - it recovers
        # from the connect *port* changing, not the phone's IP itself
        # changing (a DHCP lease renewal landing on a different address,
        # a different network, etc.). That's a real, if much rarer, gap:
        # IP changes are comparatively uncommon on a stable home network
        # (most routers keep re-issuing the same lease to the same device),
        # but they're not impossible, and there's currently no fallback for
        # that case - it would need matching by something host-independent
        # (e.g. the device's own identity) to safely avoid connecting to
        # the wrong device if more than one is broadcasting on the network.
        if ":" not in serial:
            await notify(f"{dev.name}: reconnect failed", message, urgency="critical")
            return [False, message]  # USB device - no IP to rediscover against
        host = address.split(":", 1)[0]
        found, new_address = await adb_tracker.find_and_connect_after_pairing(
            adb_path, host, attempts=3, interval=1.0
        )
        if not found:
            await notify(
                f"{dev.name}: reconnect failed", f"{message} - and it's not advertising on mDNS either; "
                "is it actually powered on and on the same network?",
                urgency="critical",
            )
            return [False, message]
        if new_address != serial:
            # The serial itself (tcpip devices use their ip:port as the adb
            # serial) is now stale too, not just last_address - rename the
            # roster entry so this doesn't also leave a duplicate row behind
            # (confirmed live: without this, track-devices auto-registers a
            # *second* entry for the new address once it independently
            # notices the device, while the old one sits stuck at
            # Disconnected forever since that exact address never comes
            # back).
            dev.last_address = new_address
            await self._sm.rekey_device(serial, new_address)
        elif new_address != dev.last_address:
            dev.last_address = new_address
            self._roster.save()
        await notify(f"{dev.name} reconnected", f"found on a new port: {new_address}")
        return [True, f"reconnected via rediscovered address {new_address}"]

    @method()
    async def Disconnect(self, serial: "s") -> "bs":  # noqa: N802
        from . import adb_tracker
        from .notify import notify
        if serial == self._sm.active_serial:
            await self._sm.stop_forwarding(serial)
        await adb_tracker.adb_disconnect(self._config.get("adbPath") or "adb", serial)
        dev = self._roster.get(serial)
        await notify(f"{dev.name if dev else serial} disconnected")
        return [True, "disconnected"]

    @method()
    async def StartForwarding(self, serial: "s") -> "bs":  # noqa: N802
        return list(await self._sm.start_forwarding(serial))

    @method()
    async def StopForwarding(self, serial: "s") -> "bs":  # noqa: N802
        return list(await self._sm.stop_forwarding(serial))

    @method()
    async def Forget(self, serial: "s") -> "b":  # noqa: N802
        return await self._sm.forget(serial)

    @method()
    async def GetMuted(self) -> "b":  # noqa: N802
        from . import pipewire_route
        muted = await pipewire_route.get_mute(self._config.get("virtualSourceName"))
        return bool(muted)

    @method()
    async def SetMute(self, muted: "b") -> "bb":  # noqa: N802
        from . import pipewire_route
        from .notify import notify
        ok = await pipewire_route.set_mute(self._config.get("virtualSourceName"), muted)
        if ok:
            self.MuteChanged(muted)
            await notify("Microphone muted" if muted else "Microphone unmuted",
                          icon="audio-volume-muted" if muted else "audio-volume-high")
        return [ok, muted if ok else not muted]

    @method()
    async def ToggleMute(self) -> "bb":  # noqa: N802
        from . import pipewire_route
        from .notify import notify
        new_state = await pipewire_route.toggle_mute(self._config.get("virtualSourceName"))
        if new_state is None:
            return [False, False]
        self.MuteChanged(new_state)
        await notify("Microphone muted" if new_state else "Microphone unmuted",
                      icon="audio-volume-muted" if new_state else "audio-volume-high")
        return [True, new_state]

    @method()
    def RescanDependencies(self) -> "s":  # noqa: N802
        results = deps.check_dependencies(self._config.get("adbPath"), self._config.get("scrcpyPath"))
        self._dependency_results = results
        self.DependencyCheckResult(_to_variant_dict(results))
        return json.dumps(results)

    @method()
    def SetConfig(self, config: "a{sv}") -> "b":  # noqa: N802
        plain = {k: (v.value if isinstance(v, Variant) else v) for k, v in config.items()}
        self._config.update(plain)
        return True

    @method()
    def GetConfig(self) -> "s":  # noqa: N802
        """JSON-encoded string, same reasoning as ListDevices/GetStatus
        above. Added for the standalone Qt tray app (see tray-app/), which
        has no kcfg to read its own defaults from the way the plasmoid
        does - it needs to be able to *read* the daemon's current config on
        startup, not just push to it one-way like SetConfig always has.
        """
        return json.dumps(self._config.as_dict())

    # --- properties --------------------------------------------------

    @dbus_property(access=PropertyAccess.READ)
    def DependenciesOk(self) -> "b":  # noqa: N802
        return deps.all_required_ok(self._dependency_results)

    @dbus_property(access=PropertyAccess.READ)
    def ActiveDevice(self) -> "s":  # noqa: N802
        return self._sm.active_serial or ""

    @dbus_property(access=PropertyAccess.READ)
    def ForwardingState(self) -> "s":  # noqa: N802
        active = self._sm.active_serial
        if not active:
            return "Disconnected"
        dev = self._roster.get(active)
        return dev.forwarding_state if dev else "Disconnected"

    # --- signals ---------------------------------------------------

    @signal()
    def DeviceAdded(self, device: "a{sv}") -> "a{sv}":  # noqa: N802
        return device

    @signal()
    def DeviceRemoved(self, serial: "s") -> "s":  # noqa: N802
        return serial

    @signal()
    def DeviceStateChanged(self, serial: "s", state: "s") -> "ss":  # noqa: N802
        return [serial, state]

    @signal()
    def ForwardingStateChanged(self, serial: "s", state: "s") -> "ss":  # noqa: N802
        return [serial, state]

    @signal()
    def ErrorOccurred(self, serial: "s", code: "s", message: "s") -> "sss":  # noqa: N802
        return [serial, code, message]

    @signal()
    def DependencyCheckResult(self, results: "a{sv}") -> "a{sv}":  # noqa: N802
        return results

    @signal()
    def MuteChanged(self, muted: "b") -> "b":  # noqa: N802
        return muted


def make_emitter(interface: DaemonInterface):
    """Adapts the plain (name, *args) signal-emission style used by
    state_machine.py onto the dbus-next-generated signal methods above.
    Wraps dict payloads (DeviceAdded) into variants; leaves plain str/bool
    args alone since dbus-next handles those signature types directly.
    """
    async def emit(signal_name: str, *args) -> None:
        bound = getattr(interface, signal_name, None)
        if bound is None:
            log.warning("no such signal: %s", signal_name)
            return
        if signal_name in ("DeviceAdded", "DependencyCheckResult") and args and isinstance(args[0], dict):
            args = (_to_variant_dict(args[0]),)
        bound(*args)
    return emit


async def create_bus_and_export(interface: DaemonInterface) -> MessageBus:
    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    bus.export(OBJECT_PATH, interface)
    await bus.request_name(BUS_NAME)
    log.info("exported %s at %s on bus name %s", INTERFACE_NAME, OBJECT_PATH, BUS_NAME)
    return bus
