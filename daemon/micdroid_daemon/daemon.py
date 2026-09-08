"""Wires together adb_tracker, the forwarding state machine, and the D-Bus
service into one asyncio event loop.
"""

from __future__ import annotations

import asyncio
import logging
import signal

from . import adb_tracker, deps, eventlog
from .config import Config
from .dbus_service import DaemonInterface, create_bus_and_export, make_emitter
from .devices import DeviceRoster
from .state_machine import ForwardingStateMachine

log = logging.getLogger(__name__)


class Daemon:
    def __init__(self) -> None:
        self.config = Config()
        self.roster = DeviceRoster()
        self.interface: DaemonInterface | None = None
        self.state_machine: ForwardingStateMachine | None = None
        self.tracker: adb_tracker.AdbTracker | None = None
        self._stop_event = asyncio.Event()

    async def run(self) -> None:
        dependency_results = deps.check_dependencies(
            self.config.get("adbPath"), self.config.get("scrcpyPath")
        )
        if not deps.all_required_ok(dependency_results):
            log.warning("missing dependencies: %s", dependency_results)

        # The interface needs the state machine's emit callback, but the state
        # machine needs the interface to build that callback - break the
        # cycle with a forwarding closure resolved after both exist.
        emitted: list = []

        eventlog.init()

        async def emit(signal_name: str, *args) -> None:
            eventlog.append(signal_name, args)
            await emitted[0](signal_name, *args)

        self.state_machine = ForwardingStateMachine(self.config, self.roster, emit)
        self.interface = DaemonInterface(self.config, self.roster, self.state_machine)
        self.interface.set_dependency_results(dependency_results)
        emitted.append(make_emitter(self.interface))

        bus = await create_bus_and_export(self.interface)
        await emit("DependencyCheckResult", dependency_results)

        adb_path = self.config.get("adbPath") or "adb"
        self.tracker = adb_tracker.AdbTracker(adb_path, self._on_adb_event)
        self.tracker.start()

        self._install_signal_handlers()
        log.info("micdroid daemon ready")
        await self._stop_event.wait()

        log.info("shutting down")
        await self.tracker.stop()
        await self.state_machine.shutdown()
        bus.disconnect()

    async def _on_adb_event(self, serial: str, state: str) -> None:
        assert self.state_machine is not None
        try:
            await self.state_machine.on_adb_event(serial, state)
        except Exception:
            log.exception("error handling adb event %s/%s", serial, state)

    def _install_signal_handlers(self) -> None:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self._stop_event.set)


async def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    daemon = Daemon()
    await daemon.run()
