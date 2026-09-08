# Micdroid

Use an Android phone's microphone as a PC microphone over adb/scrcpy,
routed into a PipeWire virtual mic - a free, unlimited-time alternative to
AudioRelay/WoMic/AndroidMic, controlled from a KDE Plasma 6 widget.

## How it works

- [scrcpy](https://github.com/Genymobile/scrcpy) (2.1+) can capture an Android
  device's microphone (`--audio-source=mic`) over USB or wireless adb and play
  it back on the PC.
- A small Python daemon (`daemon/`) wraps scrcpy + adb: it tracks devices
  event-driven (`adb`'s `host:track-devices` protocol, no polling), spawns
  scrcpy per forwarding session, and moves its audio stream onto a PipeWire
  virtual mic sink/source pair (`pactl move-sink-input`, since scrcpy's SDL
  audio backend ignores `PULSE_SINK`/`SDL_AUDIODRIVER` - confirmed by testing,
  not assumed). It exposes all of this over a session D-Bus service
  (`org.micdroid.Daemon1`).
- The Plasma widget (`package/`) is a thin UI over that D-Bus service - list
  known devices, connect/start/stop forwarding, see live status - with no
  polling on the QML side either (it tails a small runtime event log the
  daemon writes; see `daemon/micdroid_daemon/eventlog.py` for why).

v1 scope, by design:
- **One forwarding session at a time.** A single virtual mic pair only needs
  one source.
- **Pairing a new device happens once, by you, in a terminal**
  (`adb pair host:port`, `adb connect host:port` - see below). The widget
  handles everything from there (listing, reconnecting, forwarding); it does
  not have its own pairing-code UI.
- **Auto-start is opt-in**, off by default (Settings > Advanced): if enabled,
  a known device that becomes reachable starts forwarding automatically.

## Requirements

- `adb` (Android platform-tools), `scrcpy` 2.1+, PipeWire (`pw-loopback`,
  `pactl`) - the widget tells you if any of these are missing and lets you
  rescan after installing them.
- Python 3.11+ for the daemon (installed into its own venv, not system-wide).
- KDE Plasma 6.

## Install

```bash
./install.sh
```

This creates a venv at `~/.local/share/micdroid/venv`, installs a
`systemd --user` unit (`micdroid.service`, not enabled at login by default -
the widget starts it on demand), and installs the Plasma widget. Then add
"Micdroid" to a panel or the desktop.

Uninstall with `./uninstall.sh` (leaves `~/.config/micdroid/` - your paired
device roster and settings - untouched).

## First-time device setup

On your phone: Settings > Developer options > Wireless debugging > Pair
device with pairing code. Then, once, from a terminal:

```bash
adb pair <phone-ip>:<pairing-port>   # enter the 6-digit code shown on the phone
adb connect <phone-ip>:<port>        # the *connect* port, shown on the same screen
```

Paste that same `host:port` into the widget's "Connect" field - it now
appears in your device list permanently, and you won't need to repeat this
unless the device needs re-pairing (e.g. after a factory reset).

## Development

```bash
cd daemon && python3 -m venv .venv && .venv/bin/pip install -e .
.venv/bin/python -m micdroid_daemon        # run the daemon directly, Ctrl-C to stop
journalctl --user -u micdroid.service -f   # daemon logs, once installed as a service
```

For the widget: `kpackagetool6 -t Plasma/Applet -i package/` (or `-u` to
upgrade an existing install), then `plasmawindowed com.micdroid.applet` to
open it standalone (`plasmoidviewer` from `plasma-sdk` also works, and
reloads faster, if you install that package).

## License

GPL-3.0-or-later.
