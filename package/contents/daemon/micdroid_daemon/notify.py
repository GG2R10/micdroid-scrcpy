"""Desktop notifications via notify-send.

Plasma's notification daemon implements the standard
org.freedesktop.Notifications D-Bus service; notify-send is the simplest,
dependency-free way to speak it from a Python backend (no special
"KNotification" interface exists distinct from the freedesktop one).
"""

from __future__ import annotations

import asyncio
import logging

log = logging.getLogger(__name__)

APP_NAME = "micdroid"


async def notify(summary: str, body: str = "", urgency: str = "normal",
                  icon: str = "audio-input-microphone") -> None:
    try:
        proc = await asyncio.create_subprocess_exec(
            "notify-send",
            "-a", APP_NAME,
            "-i", icon,
            "-u", urgency,
            summary, body,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()
    except FileNotFoundError:
        log.debug("notify-send not available, skipping notification: %s", summary)
    except Exception:
        log.exception("failed to send notification: %s", summary)
