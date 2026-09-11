"""DaemonBridge: the Qt-side equivalent of ../../package/contents/ui/main.qml.

Exposes the exact same property/method surface the plasmoid's `root` object
does (serviceRunning, dependenciesOk, dependencyResults, activeDevice,
forwardingState, lastError, muted, devicesModel, requiredTools, plus the
config-* settings and the toggleMute/startForwarding/.../pairDevice/
restartService methods) so the QML views under qml/views/ - symlinked
straight from ../../package/contents/ui/views/ - work completely unmodified
against this bridge instead of the plasmoid's PlasmoidItem root. Methods
that the shared QML calls with a trailing JS callback (e.g.
`micdroid.retryDevice(serial, function (ok) {...})`) accept an optional
QJSValue and .call() it directly - safe here because, unlike the plasmoid's
Plasma5Support.DataSource (an inherently async shell-exec API that's the
whole reason main.qml's version of these needed callbacks in the first
place), QtDBus's synchronous calls complete before the slot returns, so
there's no real async gap - the callback is just invoked inline.

Talks to the daemon over plain PySide6.QtDBus rather than reusing the
daemon's own `dbus-next` (asyncio-native) - confirmed live (see this
branch's spike scripts) that QDBusInterface.call() marshals a plain Python
dict straight into a{sv} for SetConfig with no manual QDBusArgument
wrangling, and QDBusConnection.connect() delivers even a{sv}-carrying
signals (DeviceAdded, DependencyCheckResult) without issue - so there's no
need for a second asyncio event loop / background thread bridged into Qt's
own, which would have been needed to reuse dbus-next cleanly here.
"""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any

from PySide6.QtCore import Property, QObject, Signal, Slot
from PySide6.QtCore import SLOT as QT_SLOT
from PySide6.QtDBus import QDBusConnection, QDBusInterface

from .devices_model import DevicesModel

BUS_NAME = "org.micdroid.Daemon1"
OBJECT_PATH = "/org/micdroid/Daemon"
INTERFACE_NAME = "org.micdroid.Daemon1"

# tray-app/micdroid_tray/bridge.py -> repo root -> package/contents/code/*.sh.
# Only actually present when this is running from a git checkout (this
# app's dev install.sh, or the plasmoid's own checkout) - reusing it there
# keeps the daemon-lifecycle logic (the wait-for-name-owned race fix, the
# bootstrap version check, etc.) in exactly one place for both frontends.
# A real installed package (e.g. the micdroid-git AUR package) has no such
# file anywhere near wherever site-packages put this one, which
# _run_servicectl() below uses as the signal to fall back to managing the
# systemd unit directly instead - see its docstring.
_REPO_ROOT = Path(__file__).resolve().parents[2]
_CODE_DIR = _REPO_ROOT / "package" / "contents" / "code"
SERVICECTL = _CODE_DIR / "servicectl.sh"

REQUIRED_TOOLS = ["adb", "scrcpy", "pw-loopback", "pactl"]

# Index-free here (unlike the plasmoid's kcfg-backed combo indices) - the
# bridge stores/reads the actual semantic string scrcpy expects directly,
# since there's no kcfg Int-only-entry constraint to work around.
AUDIO_SOURCE_OPTIONS = ["mic", "mic-voice-communication", "mic-unprocessed", "mic-camcorder", "mic-voice-recognition"]
AUDIO_CODEC_OPTIONS = ["raw", "opus", "aac", "flac"]

_CONFIG_KEYS = [
    "audioSource", "audioCodec", "virtualSinkName", "virtualSourceName",
    "virtualSinkDescription", "virtualSourceDescription", "setAsDefaultSource",
    "autoStartOnKnownDevice", "probeIntervalSec", "maxReconnectAttempts",
    "reconnectBackoffSec", "adbPath", "scrcpyPath",
]


def _call_callback(callback, args: list) -> None:
    """QML passes `undefined` for an omitted trailing callback param, which
    arrives here as a null/undefined QJSValue - only .call() a real function.
    """
    if callback is not None and not callback.isUndefined() and not callback.isNull():
        callback.call(args)


class DaemonBridge(QObject):
    serviceRunningChanged = Signal()
    dependenciesOkChanged = Signal()
    dependencyResultsChanged = Signal()
    activeDeviceChanged = Signal()
    forwardingStateChanged = Signal()
    lastErrorChanged = Signal()
    mutedChanged = Signal()
    configChanged = Signal()  # fired once after any config field changes, for a Settings window to resync from

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._devices_model = DevicesModel(self)
        self._service_running = False
        self._dependencies_ok = False
        self._dependency_results: dict[str, Any] = {}
        self._active_device = ""
        self._forwarding_state = "Disconnected"
        self._last_error = ""
        self._muted = False
        self._config: dict[str, Any] = {}
        self._iface: QDBusInterface | None = None
        self._signals_connected = False

    # --- read-only status properties, mirroring main.qml's root.* -------

    def _get_service_running(self) -> bool:
        return self._service_running

    def _set_service_running(self, value: bool) -> None:
        if self._service_running != value:
            self._service_running = value
            self.serviceRunningChanged.emit()

    serviceRunning = Property(bool, _get_service_running, notify=serviceRunningChanged)

    def _get_dependencies_ok(self) -> bool:
        return self._dependencies_ok

    dependenciesOk = Property(bool, _get_dependencies_ok, notify=dependenciesOkChanged)

    def _get_dependency_results(self) -> dict:
        return self._dependency_results

    dependencyResults = Property("QVariantMap", _get_dependency_results, notify=dependencyResultsChanged)

    def _get_active_device(self) -> str:
        return self._active_device

    activeDevice = Property(str, _get_active_device, notify=activeDeviceChanged)

    def _get_forwarding_state(self) -> str:
        return self._forwarding_state

    forwardingState = Property(str, _get_forwarding_state, notify=forwardingStateChanged)

    def _get_last_error(self) -> str:
        return self._last_error

    def _set_last_error(self, value: str) -> None:
        if self._last_error != value:
            self._last_error = value
            self.lastErrorChanged.emit()

    lastError = Property(str, _get_last_error, notify=lastErrorChanged)

    def _get_muted(self) -> bool:
        return self._muted

    muted = Property(bool, _get_muted, notify=mutedChanged)

    def _get_devices_model(self) -> DevicesModel:
        return self._devices_model

    devicesModel = Property(QObject, _get_devices_model, constant=True)

    def _get_required_tools(self) -> list:
        return REQUIRED_TOOLS

    requiredTools = Property("QVariantList", _get_required_tools, constant=True)

    def _get_audio_source_options(self) -> list:
        return AUDIO_SOURCE_OPTIONS

    audioSourceOptions = Property("QVariantList", _get_audio_source_options, constant=True)

    def _get_audio_codec_options(self) -> list:
        return AUDIO_CODEC_OPTIONS

    audioCodecOptions = Property("QVariantList", _get_audio_codec_options, constant=True)

    # --- config properties (read/write, each write pushes via SetConfig) -

    def _config_get(self, key: str, default: Any = "") -> Any:
        return self._config.get(key, default)

    def _config_set(self, key: str, value: Any) -> None:
        if self._config.get(key) == value:
            return
        self._config[key] = value
        self._push_config({key: value})
        self.configChanged.emit()

    audioSource = Property(str, lambda self: self._config_get("audioSource", "mic"),
                            lambda self, v: self._config_set("audioSource", v), notify=configChanged)
    audioCodec = Property(str, lambda self: self._config_get("audioCodec", "raw"),
                           lambda self, v: self._config_set("audioCodec", v), notify=configChanged)
    virtualSinkName = Property(str, lambda self: self._config_get("virtualSinkName", "VirtualMicSink"),
                                lambda self, v: self._config_set("virtualSinkName", v), notify=configChanged)
    virtualSourceName = Property(str, lambda self: self._config_get("virtualSourceName", "VirtualMicSource"),
                                  lambda self, v: self._config_set("virtualSourceName", v), notify=configChanged)
    virtualSinkDescription = Property(str, lambda self: self._config_get("virtualSinkDescription", ""),
                                       lambda self, v: self._config_set("virtualSinkDescription", v), notify=configChanged)
    virtualSourceDescription = Property(str, lambda self: self._config_get("virtualSourceDescription", ""),
                                         lambda self, v: self._config_set("virtualSourceDescription", v), notify=configChanged)
    setAsDefaultSource = Property(bool, lambda self: bool(self._config_get("setAsDefaultSource", True)),
                                   lambda self, v: self._config_set("setAsDefaultSource", v), notify=configChanged)
    autoStartOnKnownDevice = Property(bool, lambda self: bool(self._config_get("autoStartOnKnownDevice", False)),
                                       lambda self, v: self._config_set("autoStartOnKnownDevice", v), notify=configChanged)
    probeIntervalSec = Property(int, lambda self: int(self._config_get("probeIntervalSec", 15)),
                                 lambda self, v: self._config_set("probeIntervalSec", v), notify=configChanged)
    maxReconnectAttempts = Property(int, lambda self: int(self._config_get("maxReconnectAttempts", 5)),
                                     lambda self, v: self._config_set("maxReconnectAttempts", v), notify=configChanged)
    adbPath = Property(str, lambda self: self._config_get("adbPath", ""),
                        lambda self, v: self._config_set("adbPath", v), notify=configChanged)
    scrcpyPath = Property(str, lambda self: self._config_get("scrcpyPath", ""),
                           lambda self, v: self._config_set("scrcpyPath", v), notify=configChanged)

    def _get_reconnect_backoff_sec(self) -> str:
        # Stored daemon-side as a list of ints; surfaced here as the same
        # comma-separated string the plasmoid's TextField uses, so the
        # Settings window can bind a plain TextField the same way.
        return ",".join(str(n) for n in self._config_get("reconnectBackoffSec", [2, 5, 10, 20, 40, 60]))

    def _set_reconnect_backoff_sec(self, value: str) -> None:
        backoff = [int(s.strip()) for s in value.split(",") if s.strip().isdigit()]
        self._config_set("reconnectBackoffSec", backoff or [2, 5, 10, 20, 40, 60])

    reconnectBackoffSec = Property(str, _get_reconnect_backoff_sec, _set_reconnect_backoff_sec, notify=configChanged)

    def _push_config(self, partial: dict[str, Any]) -> None:
        if self._iface is None:
            return
        self._iface.call("SetConfig", partial)

    # --- D-Bus plumbing --------------------------------------------------

    def _ensure_interface(self) -> bool:
        if self._iface is not None and self._iface.isValid():
            return True
        self._iface = QDBusInterface(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, QDBusConnection.sessionBus())
        if not self._iface.isValid():
            self._iface = None
            return False
        if not self._signals_connected:
            self._connect_signals()
            self._signals_connected = True
        return True

    def _connect_signals(self) -> None:
        bus = QDBusConnection.sessionBus()
        # Simple-typed signals: connect with a precisely-typed slot so the
        # payload actually reaches us.
        bus.connect(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, "DeviceRemoved",
                    self, QT_SLOT("_onDeviceRemoved(QString)"))
        bus.connect(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, "DeviceStateChanged",
                    self, QT_SLOT("_onDeviceStateChanged(QString,QString)"))
        bus.connect(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, "ForwardingStateChanged",
                    self, QT_SLOT("_onForwardingStateChanged(QString,QString)"))
        bus.connect(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, "ErrorOccurred",
                    self, QT_SLOT("_onErrorOccurred(QString,QString,QString)"))
        bus.connect(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, "MuteChanged",
                    self, QT_SLOT("_onMuteChanged(bool)"))
        # a{sv}-carrying signals: confirmed live that QDBusConnection.connect
        # happily subscribes even though we don't attempt to marshal the
        # payload - a plain QDBusMessage catch-all slot, then just re-fetch
        # the equivalent state via the JSON-string methods (ListDevices/
        # GetStatus) instead of trying to unpack a{sv} by hand.
        bus.connect(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, "DeviceAdded",
                    self, QT_SLOT("_onDeviceAdded(QDBusMessage)"))
        bus.connect(BUS_NAME, OBJECT_PATH, INTERFACE_NAME, "DependencyCheckResult",
                    self, QT_SLOT("_onDependencyCheckResult(QDBusMessage)"))

    def _call(self, method: str, *args) -> Any:
        if not self._ensure_interface():
            return None
        reply = self._iface.call(method, *args)
        if reply.errorMessage():
            self._set_last_error(reply.errorMessage())
            return None
        reply_args = reply.arguments()
        return reply_args[0] if len(reply_args) == 1 else reply_args

    def _call_json(self, method: str) -> Any:
        raw = self._call(method)
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except (TypeError, json.JSONDecodeError):
            return None

    # --- signal handlers (Qt slots invoked by QDBusConnection.connect) ---

    @Slot(str)
    def _onDeviceRemoved(self, serial: str) -> None:  # noqa: N802
        self._devices_model.remove(serial)

    @Slot(str, str)
    def _onDeviceStateChanged(self, serial: str, state: str) -> None:  # noqa: N802
        self._devices_model.update_field(serial, "state", state)

    @Slot(str, str)
    def _onForwardingStateChanged(self, serial: str, state: str) -> None:  # noqa: N802
        # Mirrors main.qml's handleEvent() ForwardingStateChanged case
        # exactly.
        self._devices_model.update_field(serial, "forwardingState", state)
        if state in ("Forwarding", "DegradedProbing", "Reconnecting", "NeedsRepair"):
            self._active_device = serial
            self.activeDeviceChanged.emit()
            self._forwarding_state = state
            self.forwardingStateChanged.emit()
        elif self._active_device == serial:
            self._active_device = ""
            self.activeDeviceChanged.emit()
            self._forwarding_state = state
            self.forwardingStateChanged.emit()

    @Slot(str, str, str)
    def _onErrorOccurred(self, serial: str, code: str, message: str) -> None:  # noqa: N802
        self._set_last_error(message or "")

    @Slot(bool)
    def _onMuteChanged(self, muted: bool) -> None:  # noqa: N802
        if self._muted != muted:
            self._muted = muted
            self.mutedChanged.emit()

    @Slot("QDBusMessage")
    def _onDeviceAdded(self, _msg) -> None:  # noqa: N802
        self.refreshDevices()

    @Slot("QDBusMessage")
    def _onDependencyCheckResult(self, _msg) -> None:  # noqa: N802
        self.refreshStatus()

    # --- one-shot queries, same names/shape as main.qml's --------------

    @Slot()
    def refreshDevices(self) -> None:
        devices = self._call_json("ListDevices")
        if devices is None:
            return
        self._devices_model.reset(devices)
        active = self._devices_model.active_states()
        if active:
            dev = self._devices_model.find(active[0])
            if dev:
                self._active_device = dev["serial"]
                self.activeDeviceChanged.emit()
                self._forwarding_state = dev["forwardingState"]
                self.forwardingStateChanged.emit()

    @Slot()
    def refreshStatus(self) -> None:
        status = self._call_json("GetStatus")
        if status is None:
            return
        if status.get("dependencyResults"):
            self._apply_dependency_results(status["dependencyResults"])
        self._active_device = status.get("activeDevice") or ""
        self.activeDeviceChanged.emit()
        self._forwarding_state = status.get("forwardingState") or "Disconnected"
        self.forwardingStateChanged.emit()

    @Slot()
    def refreshMuteState(self) -> None:
        result = self._call("GetMuted")
        if result is not None:
            self._muted = bool(result)
            self.mutedChanged.emit()

    def _apply_dependency_results(self, results: dict) -> None:
        self._dependency_results = results
        self.dependencyResultsChanged.emit()
        ok = all(results.get(t) for t in REQUIRED_TOOLS)
        if ok != self._dependencies_ok:
            self._dependencies_ok = ok
            self.dependenciesOkChanged.emit()

    # --- commands, same names/callback shape as main.qml's --------------

    @Slot()
    @Slot("QJSValue")
    def toggleMute(self, callback=None) -> None:
        result = self._call("ToggleMute")
        if result is not None:
            ok, new_muted = result
            if ok:
                self._muted = bool(new_muted)
                self.mutedChanged.emit()
        _call_callback(callback, [self._muted])

    @Slot(str)
    def startForwarding(self, serial: str) -> None:
        self._call("StartForwarding", serial)

    @Slot(str)
    def stopForwarding(self, serial: str) -> None:
        self._call("StopForwarding", serial)

    @Slot(str)
    @Slot(str, "QJSValue")
    def disconnectDevice(self, serial: str, callback=None) -> None:
        result = self._call("Disconnect", serial)
        ok = bool(result[0]) if result else False
        if ok:
            self._devices_model.update_field(serial, "forwardingState", "Disconnected")
        _call_callback(callback, [ok])

    @Slot(str)
    @Slot(str, "QJSValue")
    def connectByAddress(self, address: str, callback=None) -> None:
        result = self._call("ConnectByAddress", address)
        ok = bool(result[0]) if result else False
        if ok:
            self.refreshDevices()
        _call_callback(callback, [ok])

    @Slot(str, str, str)
    @Slot(str, str, str, "QJSValue")
    def pairDevice(self, host: str, pair_port: str, code: str, callback=None) -> None:
        result = self._call("Pair", host, pair_port, code)
        paired, connected, message = (False, False, "")
        if result:
            paired, connected, message = bool(result[0]), bool(result[1]), result[2] or ""
            if connected:
                self.refreshDevices()
        else:
            message = self._last_error
        _call_callback(callback, [paired, connected, message])

    @Slot(str)
    @Slot(str, "QJSValue")
    def retryDevice(self, serial: str, callback=None) -> None:
        result = self._call("Connect", serial)
        ok = bool(result[0]) if result else False
        if result:
            self._set_last_error("" if ok else (result[1] or "Reconnect failed"))
        _call_callback(callback, [ok])

    @Slot(str)
    def forgetDevice(self, serial: str) -> None:
        result = self._call("Forget", serial)
        if result:
            self._devices_model.remove(serial)

    @Slot()
    def rescanDependencies(self) -> None:
        results = self._call_json("RescanDependencies")
        if results:
            self._apply_dependency_results(results)

    # --- systemd service lifecycle, same names as main.qml's ------------

    def _wait_for_name_owned(self, timeout: float = 6.0) -> bool:
        """Pure-Python port of servicectl.sh's wait_for_name_owned() - only
        used by the systemctl fallback below, for the exact same reason
        that function exists: systemctl reporting a unit "started" only
        means systemd handed the process off, not that the daemon has
        actually claimed org.micdroid.Daemon1 on the bus yet.
        """
        bus_iface = QDBusInterface("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                    "org.freedesktop.DBus", QDBusConnection.sessionBus())
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            reply = bus_iface.call("NameHasOwner", BUS_NAME)
            args = reply.arguments()
            if args and bool(args[0]):
                return True
            time.sleep(0.2)
        return False

    def _run_servicectl(self, *args: str) -> bool:
        if SERVICECTL.is_file():
            try:
                proc = subprocess.run(
                    ["bash", str(SERVICECTL), *args],
                    capture_output=True, text=True, timeout=15,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                self._set_last_error(str(exc))
                return False
            if proc.returncode != 0:
                self._set_last_error(proc.stderr.strip() or f"servicectl.sh {' '.join(args)} failed")
            return proc.returncode == 0

        # No servicectl.sh next to this file at all - meaning this isn't a
        # checkout, it's a real installed package (e.g. the micdroid-git
        # AUR package). There's nothing to bootstrap in that case: the
        # daemon's dependencies are plain system packages and its unit
        # already lives in /usr/lib/systemd/user/, both put there by
        # pacman itself - so just manage the unit directly instead of
        # looking for a script that was never installed to begin with.
        action = {"ensure-running": "start", "restart": "restart", "stop": "stop"}[args[0]]
        if args[0] == "ensure-running":
            already_active = subprocess.run(
                ["systemctl", "--user", "is-active", "--quiet", "micdroid.service"]
            ).returncode == 0
            if already_active and self._wait_for_name_owned(timeout=1.0):
                return True
        try:
            proc = subprocess.run(
                ["systemctl", "--user", action, "micdroid.service"],
                capture_output=True, text=True, timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            self._set_last_error(str(exc))
            return False
        if proc.returncode != 0:
            self._set_last_error(proc.stderr.strip() or f"systemctl {action} micdroid.service failed")
            return False
        if action == "stop":
            return True
        if not self._wait_for_name_owned():
            self._set_last_error(f"micdroid.service {action}ed but never claimed {BUS_NAME} - "
                                  "check journalctl --user -u micdroid.service")
            return False
        return True

    @Slot()
    @Slot("QJSValue")
    def restartService(self, callback=None) -> None:
        # Blocking on the main thread for up to a few seconds - same known,
        # documented trade-off as this branch's plan: simplest correct
        # thing first, a non-blocking version (background thread + queued
        # signal back to the caller) is a reasonable fast-follow if this
        # ever feels sluggish in practice.
        ok = self._run_servicectl("restart")
        self._set_service_running(ok)
        if ok:
            self.bootstrap()
        _call_callback(callback, [ok])

    @Slot()
    @Slot("QJSValue")
    def stopService(self, callback=None) -> None:
        ok = self._run_servicectl("stop")
        if ok:
            self._set_service_running(False)
        _call_callback(callback, [ok])

    @Slot()
    @Slot("QJSValue")
    def toggleService(self, callback=None) -> None:
        if self._service_running:
            self.stopService(callback)
            return
        ok = self._run_servicectl("ensure-running")
        self._set_service_running(ok)
        if ok:
            self.bootstrap()
        _call_callback(callback, [ok])

    # --- bootstrap, same name as main.qml's ------------------------------

    @Slot()
    def bootstrap(self) -> None:
        ok = self._run_servicectl("ensure-running")
        self._set_service_running(ok)
        if not ok:
            return
        if self._ensure_interface():
            config = self._call_json("GetConfig")
            if config:
                self._config = config
                self.configChanged.emit()
            self.refreshDevices()
            self.refreshStatus()
            self.refreshMuteState()
