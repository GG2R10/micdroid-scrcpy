"""Startup dependency checks: is everything micdroid needs actually on PATH?

Checked once at daemon startup and re-checked on demand via the
RescanDependencies D-Bus method, so the plasmoid can show a clear
"X is missing" state instead of failing opaquely deep inside a subprocess
spawn.
"""

from __future__ import annotations

import re
import shutil
import subprocess

REQUIRED_TOOLS = ("adb", "scrcpy", "pw-loopback", "pactl")
OPTIONAL_TOOLS = ("avahi-browse",)  # used only as an mDNS IP-resolution fallback

# scrcpy 2.1 is the first version with --audio-source=mic.
MIN_SCRCPY_VERSION = (2, 1)


def _which(name: str, override_path: str = "") -> str | None:
    if override_path:
        return override_path if shutil.which(override_path) else None
    return shutil.which(name)


def _scrcpy_version(scrcpy_path: str) -> tuple[int, ...] | None:
    try:
        out = subprocess.run(
            [scrcpy_path, "--version"], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r"scrcpy (\d+)\.(\d+)", out)
    if not match:
        return None
    return (int(match.group(1)), int(match.group(2)))


def check_dependencies(adb_path: str = "", scrcpy_path: str = "") -> dict[str, str | None]:
    """Returns a dict tool-name -> resolved path, or None if missing/unusable.
    A special key "scrcpy_audio_mic" reports whether the resolved scrcpy is new
    enough for --audio-source=mic (None means "couldn't determine", not "missing").
    """
    results: dict[str, str | None] = {}

    resolved_adb = _which("adb", adb_path)
    results["adb"] = resolved_adb

    resolved_scrcpy = _which("scrcpy", scrcpy_path)
    results["scrcpy"] = resolved_scrcpy

    for tool in ("pw-loopback", "pactl"):
        results[tool] = shutil.which(tool)
    for tool in OPTIONAL_TOOLS:
        results[tool] = shutil.which(tool)

    if resolved_scrcpy:
        version = _scrcpy_version(resolved_scrcpy)
        if version is not None and version < MIN_SCRCPY_VERSION:
            results["scrcpy"] = None
            results["scrcpy_version_error"] = (
                f"scrcpy {'.'.join(map(str, version))} found, but "
                f"{'.'.join(map(str, MIN_SCRCPY_VERSION))}+ is required for mic forwarding"
            )

    return results


def all_required_ok(results: dict[str, str | None]) -> bool:
    return all(results.get(tool) for tool in REQUIRED_TOOLS)
