"""adb integration: event-driven device tracking, liveness probing, and
best-effort IP re-resolution for wireless reconnects.

Validated live against a real device (see project plan's "Spikes" section)
before this was written:
  - `host:track-devices` raw protocol (4 ASCII-hex-byte length prefix + payload,
    same framing as the rest of the adb wire protocol) against the adb server
    socket on 127.0.0.1:5037 delivers a fresh `serial\\tstate\\n` device list
    within ~1s of any adb-visible state change (device attach/detach,
    device/offline/unauthorized transitions) - confirmed with a live
    disconnect/reconnect cycle. No external library needed.
  - `adb connect <addr>` always exits 0 even on failure; the real answer is in
    stdout ("connected to ..." vs "failed to connect ...").

Not relied upon (per research, adb's own mDNS resolution is flaky on Linux):
  `adb mdns services`/`track-services`. Used only opportunistically as a first
  attempt; a `zeroconf`-based Avahi query is the real fallback for reconnecting
  after a DHCP IP change on pre-"ADB Wi-Fi 2.0" devices.
"""

from __future__ import annotations

import asyncio
import logging
import re
import shutil
import subprocess
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

log = logging.getLogger(__name__)

ADB_HOST = "127.0.0.1"
ADB_PORT = 5037

# adb reports its own device states verbatim; "gone" is our synthetic state for
# "no longer present in the tracked list at all" (distinct from "offline").
LIVE_STATES = {"device", "offline", "unauthorized", "authorizing", "no permissions"}

# platform-tools >=37.0.0 shipped "ADB Wi-Fi 2.0" (trusted-network
# auto-reconnect with stored TLS creds). Used only as a fast heuristic; actual
# per-device capability still degrades gracefully if unconfirmed.
WIFI_ADB2_MIN_VERSION = (37, 0, 0)

DeviceEventCallback = Callable[[str, str], Awaitable[None]]  # (serial, state) -> None
# state == "gone" means the serial disappeared from the tracked list entirely.


@dataclass
class TrackDevicesEvent:
    serial: str
    state: str  # one of LIVE_STATES, or "gone"


def _parse_device_list(payload: bytes) -> dict[str, str]:
    devices: dict[str, str] = {}
    for line in payload.decode(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        serial, state = parts
        devices[serial] = state
    return devices


class AdbClientProtocolError(RuntimeError):
    pass


async def _adb_send_request(reader: asyncio.StreamReader, writer: asyncio.StreamWriter,
                             payload: str) -> None:
    data = payload.encode()
    writer.write(b"%04x" % len(data) + data)
    await writer.drain()
    status = await reader.readexactly(4)
    if status != b"OKAY":
        try:
            length = int(await reader.readexactly(4), 16)
            message = (await reader.readexactly(length)).decode(errors="replace")
        except (asyncio.IncompleteReadError, ValueError):
            message = "?"
        raise AdbClientProtocolError(f"adb server replied {status!r}: {message}")


async def _read_frame(reader: asyncio.StreamReader) -> bytes | None:
    """Reads one length-prefixed frame. Returns None on clean EOF."""
    try:
        length_hex = await reader.readexactly(4)
    except asyncio.IncompleteReadError:
        return None
    length = int(length_hex, 16)
    if length == 0:
        return b""
    return await reader.readexactly(length)


async def _ensure_adb_server_running(adb_path: str) -> None:
    proc = await asyncio.create_subprocess_exec(
        adb_path, "start-server",
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
    )
    await proc.wait()


class AdbTracker:
    """Owns the long-lived host:track-devices subscription and reconnects the
    subscription itself (not individual devices - that's the state machine's
    job) if the adb *server* connection drops.
    """

    def __init__(self, adb_path: str, on_event: DeviceEventCallback) -> None:
        self._adb_path = adb_path
        self._on_event = on_event
        self._task: asyncio.Task | None = None
        self._known: dict[str, str] = {}
        self._stopping = False

    def start(self) -> None:
        self._stopping = False
        self._task = asyncio.create_task(self._run_forever(), name="adb-track-devices")

    async def stop(self) -> None:
        self._stopping = True
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run_forever(self) -> None:
        backoff = 1.0
        while not self._stopping:
            try:
                await self._subscribe_once()
                backoff = 1.0  # clean EOF (e.g. adb kill-server) -> reset backoff, retry promptly
            except asyncio.CancelledError:
                raise
            except (ConnectionRefusedError, AdbClientProtocolError, OSError) as exc:
                log.warning("track-devices connection lost (%s), restarting adb server", exc)
                await _ensure_adb_server_running(self._adb_path)
            except Exception:
                log.exception("unexpected error in track-devices loop")
            if self._stopping:
                break
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 15.0)

    async def _subscribe_once(self) -> None:
        reader, writer = await asyncio.open_connection(ADB_HOST, ADB_PORT)
        try:
            await _adb_send_request(reader, writer, "host:track-devices")
            log.info("subscribed to adb host:track-devices")
            while True:
                frame = await _read_frame(reader)
                if frame is None:
                    log.info("adb server closed track-devices stream")
                    return
                current = _parse_device_list(frame)
                await self._diff_and_emit(current)
        finally:
            writer.close()

    async def _diff_and_emit(self, current: dict[str, str]) -> None:
        for serial, state in current.items():
            if self._known.get(serial) != state:
                await self._on_event(serial, state)
        for serial in self._known:
            if serial not in current:
                await self._on_event(serial, "gone")
        self._known = current


# --- one-shot helpers, called from state_machine.py / dbus_service.py ---

async def adb_connect(adb_path: str, address: str, timeout: float = 10.0) -> tuple[bool, str]:
    """`adb connect` always exits 0 even on failure - the real signal is stdout."""
    try:
        proc = await asyncio.create_subprocess_exec(
            adb_path, "connect", address,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        return False, f"timed out connecting to {address}"
    text = stdout.decode(errors="replace").strip() or stderr.decode(errors="replace").strip()
    return text.lower().startswith("connected"), text


async def adb_disconnect(adb_path: str, serial: str) -> None:
    proc = await asyncio.create_subprocess_exec(
        adb_path, "disconnect", serial,
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
    )
    await proc.wait()


async def liveness_probe(adb_path: str, serial: str, timeout: float = 3.0) -> bool:
    """Active liveness check - wireless adb is known to report a device as
    `device` for a while after the link is actually dead ("Wi-Fi ADB lies"),
    so track-devices state alone isn't enough while a session is active.
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            adb_path, "-s", serial, "shell", "echo", "ok",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except (asyncio.TimeoutError, OSError):
        return False
    return stdout.strip() == b"ok"


def get_platform_tools_version(adb_path: str) -> tuple[int, int, int] | None:
    try:
        out = subprocess.run([adb_path, "version"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r"Version (\d+)\.(\d+)\.(\d+)", out)
    if not match:
        return None
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)))


def is_wifi_adb2_capable(adb_path: str) -> bool:
    """Fast heuristic only (platform-tools version threshold) - real per-device
    confirmation would need `adb mdns track-services --proto-text` reporting
    mdns_service_version "2.0", which requires the phone's Wireless debugging
    screen to be open and was not reliably reproducible in testing. Never block
    on this - it only decides whether to skip the manual IP-tracking fallback.
    """
    version = get_platform_tools_version(adb_path)
    return version is not None and version >= WIFI_ADB2_MIN_VERSION


async def resolve_ip_via_avahi(service_type: str = "_adb-tls-connect._tcp",
                                timeout: float = 4.0) -> list[str]:
    """Best-effort IP:port resolution fallback for reconnecting after a DHCP
    change, bypassing adb's own (Linux-flaky) mDNS client. Returns a list of
    "ip:port" candidates; empty if avahi-browse isn't installed or nothing
    is currently being advertised (e.g. the phone's Wireless debugging screen
    isn't open).
    """
    if shutil.which("avahi-browse") is None:
        return []
    try:
        proc = await asyncio.create_subprocess_exec(
            "avahi-browse", "-rpt", service_type,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except (asyncio.TimeoutError, OSError):
        return []
    candidates: list[str] = []
    for line in stdout.decode(errors="replace").splitlines():
        # avahi-browse -rpt resolved-record format is semicolon separated;
        # field 8 is the address, field 9 the port, for a "=" (resolved) row.
        if not line.startswith("="):
            continue
        fields = line.split(";")
        if len(fields) < 9:
            continue
        address, port = fields[7], fields[8]
        candidates.append(f"{address}:{port}")
    return candidates
