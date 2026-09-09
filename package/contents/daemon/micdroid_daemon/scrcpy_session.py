"""Spawns and supervises a single scrcpy subprocess doing mic-only forwarding
for one device, and interprets its exit code.

Exit codes per the scrcpy manpage (confirmed current in scrcpy 4.1, used here
to distinguish "never connected" from "dropped mid-session" without having to
guess from stderr):
    0 - normal termination (we asked it to stop, or the user closed something)
    1 - initial connection could not be established
    2 - device disconnected while a session was active
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from enum import IntEnum

log = logging.getLogger(__name__)


class ScrcpyExit(IntEnum):
    NORMAL = 0
    NEVER_CONNECTED = 1
    DISCONNECTED_MID_SESSION = 2
    UNKNOWN = -1


ExitCallback = Callable[[str, ScrcpyExit], Awaitable[None]]  # (serial, exit_kind)


class ScrcpySession:
    def __init__(self, scrcpy_path: str, serial: str, audio_source: str,
                 audio_codec: str, on_exit: ExitCallback) -> None:
        self._scrcpy_path = scrcpy_path
        self._serial = serial
        self._audio_source = audio_source
        self._audio_codec = audio_codec
        self._on_exit = on_exit
        self._process: asyncio.subprocess.Process | None = None
        self._watch_task: asyncio.Task | None = None
        self._stopping = False

    @property
    def is_running(self) -> bool:
        return self._process is not None and self._process.returncode is None

    async def start(self) -> None:
        args = [
            self._scrcpy_path,
            "-s", self._serial,
            "--no-video",
            "--no-window",
            f"--audio-source={self._audio_source}",
            f"--audio-codec={self._audio_codec}",
        ]
        log.info("starting scrcpy: %s", " ".join(args))
        self._stopping = False
        self._process = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self._watch_task = asyncio.create_task(
            self._watch(), name=f"scrcpy-watch-{self._serial}"
        )

    async def _watch(self) -> None:
        assert self._process is not None
        stdout, stderr = await self._process.communicate()
        code = self._process.returncode
        if self._stopping:
            # We asked it to stop (StopForwarding/Disconnect) - don't report
            # this as a disconnect event even if the exit code says otherwise.
            return
        try:
            kind = ScrcpyExit(code)
        except ValueError:
            kind = ScrcpyExit.UNKNOWN
        if kind is not ScrcpyExit.NORMAL:
            log.warning(
                "scrcpy for %s exited %s (%s)\nstdout: %s\nstderr: %s",
                self._serial, code, kind.name,
                stdout.decode(errors="replace")[-2000:],
                stderr.decode(errors="replace")[-2000:],
            )
        await self._on_exit(self._serial, kind)

    async def stop(self) -> None:
        self._stopping = True
        if self._process is None or self._process.returncode is not None:
            return
        self._process.terminate()
        try:
            await asyncio.wait_for(self._process.wait(), timeout=3.0)
        except asyncio.TimeoutError:
            self._process.kill()
            await self._process.wait()
        if self._watch_task is not None:
            try:
                await self._watch_task
            except asyncio.CancelledError:
                pass
