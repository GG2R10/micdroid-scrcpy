# Micdroid

<p align="center"><img src="assets/micdroid_icon_readme.png" width="128" height="128" alt="Micdroid icon"></p>

<p align="center"><b>Use an Android phone's microphone as a PC microphone over adb/scrcpy, routed into a PipeWire virtual mic.</b><br>
A free, unlimited-time alternative to AudioRelay/WoMic/AndroidMic.</p>

<p align="center">
  <img src="assets/mainpopup_screenshot.png" width="45%" alt="Device list popup">
  &nbsp;&nbsp;
  <img src="assets/pairingpopup_screenshot.png" width="45%" alt="Pairing popup">
</p>

## Two ways to use this

Both talk to the exact same background service - pick whichever fits how you work, or
install both (they don't conflict):

- **[KDE Plasma widget](package/)** - lives in a panel or on the desktop, KDE-native.
  The original, most-tested way to use this if you're on Plasma 6.
- **[System tray app](tray-app/)** - a standalone Qt app with a tray icon, closer to how
  Discord or Steam behave (StatusNotifierItem Host required).

## Features

- Wireless or USB adb, low-latency mic forwarding via scrcpy
- In-app pairing (adb pairing code flow) - no terminal required for everyday use
- Auto-recovery when a device's wireless debugging port changes (a fresh
  connect attempt failing falls back to mDNS rediscovery automatically)
- Mute toggle for the virtual mic, independent of the forwarding session
- Multi-device aware: keeps a roster of every phone you've paired, one
  forwarding session active at a time
- Dependency and backend-service health surfaced directly in the UI,
  with a one-click rescan/restart
- Widget-only: configurable middle-click quick action on the panel icon (mute /
  disconnect the active device / stop-start the backend), so right-click stays the
  normal panel "Configure/Remove" menu

<details>
<summary><strong>Requirements</strong></summary>

Already-installed system tools this project depends on **but does not
install for you**:

- `adb` (Android platform-tools)
- [`scrcpy`](https://github.com/Genymobile/scrcpy) 2.1 or newer (mic
  forwarding needs `--audio-source`, added in 2.1)
- PipeWire's `pactl` and `pw-loopback` (virtual mic + mute)
- `notify-send` (desktop notifications) - present by default on Plasma
- `avahi-browse` (optional) - only used as a fallback to rediscover a
  device's address when its wireless debugging port changes

Either frontend checks for all of these on startup and tells you exactly which
one is missing if any aren't found, with a one-click rescan once you've
installed it.

- Python 3.11+ (for the daemon's own private virtualenv, set up
  automatically - see below)
- For the **Plasma widget**: KDE Plasma 6.
- For the **tray app**: PySide6 (`sudo pacman -S python-pyside6` on Arch; your
  distro's equivalent package, or `pip install PySide6`, elsewhere).

</details>

## Install

<details>
<summary><strong>Script</strong></summary>

You can directly use the script and select how you want to install: 
  
```bash
curl -fsSL https://raw.githubusercontent.com/GG2R10/micdroid-scrcpy/master/install.sh | bash
```

Clones this repo to `~/.local/share/micdroid-scrcpy` (re-running the same command later
just updates that checkout instead of cloning again), then asks which frontend you want
(widget, tray app, or both) and sets up the shared backend (venv + systemd unit) either
way. Non-interactive: `curl -fsSL .../install.sh | bash -s -- widget` (or `tray`/`both`).

Prefer cloning yourself first? Same script either way:

```bash
git clone https://github.com/GG2R10/micdroid-scrcpy.git
cd micdroid-scrcpy
./install.sh
```
</details>

<details>
<summary><strong>AUR Tray Application (No Widget)</strong></summary>
  
You can install the latest git app  version with any AUR Helper: `micdroid-git`
</details>

<details>
<summary><strong>KDE Plasma widget only</strong></summary>

**KDE Store**: search for "Micdroid" in Plasma's "Get New Widgets" dialog,
install it, and add it to a panel - it bootstraps its own backend the first time it
loads, no separate script to run (the first load takes a few extra seconds while that
happens, needing network access once).

**Manual**: Clone the repo and: 

```bash
./package/install.sh
```

</details>

<details>
<summary><strong>Tray app only</strong></summary>

```bash
./tray-app/install.sh
```

Adds an application-launcher entry and starts it at login (removable any time from
System Settings → Autostart). See [tray-app/README.md](tray-app/README.md) for details.

</details>

<details>
<summary><strong>Uninstall</strong></summary>

`./uninstall.sh` removes the backend, systemd unit, and the Plasma widget (leaves
`~/.config/micdroid/` - your paired device roster and settings - untouched). If you also
installed the tray app, remove its entries too:
`rm ~/.local/share/applications/micdroid-tray.desktop ~/.config/autostart/micdroid-tray.desktop`.
If you installed the widget purely via the KDE Store, remove it from Plasma's widget
list, then manually remove `~/.local/share/micdroid/` and
`~/.config/systemd/user/micdroid.service`. If you used the `curl | bash` one-liner,
`./uninstall.sh` there is this same script, at `~/.local/share/micdroid-scrcpy/uninstall.sh` -
remove that whole directory afterward too, once you're done, to drop the checkout itself.

</details>

## First-time device setup

On your phone: Settings > Developer options > Wireless debugging > "Pair
device with pairing code". In either frontend, click **Pair new device** and
enter the IP, pairing port, and 6-digit code it shows. The daemon runs
`adb pair`, then tries to auto-discover the (separate) *connect* port via
mDNS and finish connecting in one step.

If that auto-discovery doesn't find it your device, use the
"Or connect by address" field at the bottom of the device list with the
IP:port shown on the phone's main Wireless debugging screen (not the pairing
dialog's port). Either way, the device then appears in your list
permanently, and pairing itself never needs to be repeated, not even if the
phone's IP or wireless debugging port later changes, unless the
device is unpaired on the phone (e.g. after a factory reset).

## Usage

Both frontends show the same device list/pairing/mute UI - the difference is just how
you get to it:

- **Plasma widget:** left-click opens the popup; middle-click runs your quick action
  (Settings > Advanced - mute by default); right-click keeps Plasma's normal panel menu.
- **Tray app:** left-click shows/hides the window; right-click opens a menu for
  mute/disconnect/Settings/Quit (quitting also stops the background service - the
  window's own `[x]` just hides it, same as Discord/Steam).

Both: the header switch turns the backend service on/off; the speaker icon next to it
mutes/unmutes independently of whether anything's actively forwarding.

## How it works

- [scrcpy](https://github.com/Genymobile/scrcpy) (2.1+) can capture an Android
  device's microphone (`--audio-source=mic`) over USB or wireless adb and play
  it back on the PC.
- A small Python daemon wraps scrcpy + adb: it tracks devices event-driven
  (`adb`'s `host:track-devices` protocol, no polling), spawns scrcpy per
  forwarding session, and moves its audio stream onto a PipeWire virtual mic
  sink/source pair. It exposes all of this over a session D-Bus service
  (`org.micdroid.Daemon1`) - completely independent of either frontend, and of
  Plasma specifically.
- **Both frontends are thin UIs over that same D-Bus service** - list known
  devices, pair/connect/start/stop forwarding, mute, see live status - and share
  almost all of their actual interface code: the Plasma widget's QML views
  ([`package/contents/ui/views/`](package/contents/ui/views/)) are used unmodified by
  the tray app too (see [`tray-app/micdroid_tray/bridge.py`](tray-app/micdroid_tray/bridge.py)
  for how). Neither polls - the widget tails a small runtime event log the daemon
  writes, and the tray app subscribes to the daemon's real D-Bus signals - both
  gap-free even under rapid bursts of state changes.

## What this installs and runs on your system

Nothing here happens silently - this section is the complete list.

**On first run** (automatically, regardless of which frontend(s) you install - see
[Install](#install)):

- `~/.local/share/micdroid/venv/` - a private Python virtualenv holding the
  daemon and its two small dependencies, [`dbus-next`](https://pypi.org/project/dbus-next/)
  and [`zeroconf`](https://pypi.org/project/zeroconf/), fetched from PyPI
  (needs network access once).
- `~/.config/systemd/user/micdroid.service` - a `systemd --user` unit for the
  daemon. **Not enabled at login** - a frontend starts/stops it on demand, so
  it uses zero resources when neither is in use.

**If you install the Plasma widget:**
- The plasmoid package itself, wherever your install method puts widgets
  (typically `~/.local/share/plasma/plasmoids/com.github.GG2R10.micdroid/`).

**If you install the tray app:**
- `~/.local/share/applications/micdroid-tray.desktop` and a matching copy in
  `~/.config/autostart/` (starts it quietly at login, like Discord/Steam - remove the
  autostart copy any time to stop that without uninstalling the app itself).
- No venv of its own - it runs against your system's Python + PySide6 package directly
  (see Requirements above).

**Created/used at runtime** (plain application state, not "installed"):

- `~/.config/micdroid/config.json` - your settings (audio source/codec,
  virtual sink/source names, auto-start, reconnect tuning, quick-action
  choice).
- `~/.config/micdroid/devices.json` - your paired-device roster (name,
  serial, last known address).
- `$XDG_RUNTIME_DIR/micdroid/events.log` - a small log the daemon appends to
  and the widget tails to stay in sync live; truncated on every daemon start,
  not meant to be read directly. (The tray app doesn't use this file - it gets the
  same events over real D-Bus signals instead.)

**External processes the daemon spawns while it's forwarding or acting on a
command**: `adb` (pair/connect/shell), `scrcpy` (one instance per active
forwarding session), `pw-loopback` (only if a sink with your configured name
doesn't already exist), `pactl` (routing and mute), `notify-send`
(notifications), `avahi-browse` (mDNS reconnect fallback, optional).

Uninstalling (see Uninstall above) removes the venv, the systemd unit, and
whichever frontend(s) you had installed, but leaves `~/.config/micdroid/` (your roster
and settings) alone.

<details>
<summary><strong>Development</strong></summary>

```bash
cd package/contents/daemon
python3 -m venv .venv && .venv/bin/pip install -e .
.venv/bin/python -m micdroid_daemon        # run the daemon directly, Ctrl-C to stop
journalctl --user -u micdroid.service -f   # daemon logs, once installed as a service
```

For the widget: `kpackagetool6 -t Plasma/Applet -i package/` (or `-u` to
upgrade an existing install), then `plasmawindowed com.github.GG2R10.micdroid`
to open it standalone (`plasmoidviewer` from `plasma-sdk` also works, and
reloads faster, if you install that package).

For the tray app: `cd tray-app && python3 -m micdroid_tray.main` runs it directly
against whatever daemon is already installed - no separate build step. See
[tray-app/README.md](tray-app/README.md) for how its pieces fit together.

</details>

## Credits

- [scrcpy](https://github.com/Genymobile/scrcpy) (Apache-2.0) does the
  actual screen/audio mirroring work this project builds on.
- `adb` is part of the Android Open Source Project (Apache-2.0).
- [PipeWire](https://pipewire.org/) (MIT) provides the virtual microphone
  and audio routing.
- [Qt](https://www.qt.io/) / [PySide6](https://pypi.org/project/PySide6/) (LGPL) power
  the tray app frontend.

## License

GPL-3.0-or-later for this project's own code.
