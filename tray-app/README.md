# Micdroid tray app

An alternative frontend to the same [micdroid daemon](../package/contents/daemon/)
the [KDE Plasma widget](../package/) uses — a standalone Qt application that lives in
the system tray, closer to how Discord or Steam behave, for anyone who doesn't want a
Plasma panel widget (or isn't running Plasma at all — the daemon itself has no Plasma
dependency; only this app's tray-icon protocol assumes a StatusNotifierItem host, which
Plasma, and most other modern desktops via an extension, provide).

Both frontends talk to the exact same `org.micdroid.Daemon1` D-Bus service — nothing
about the daemon, the reconnection logic, or the PipeWire routing is duplicated here.
Most of the UI isn't duplicated either: `qml/views/` is a symlink straight to
[`../package/contents/ui/views/`](../package/contents/ui/views/), so `DeviceListView.qml`,
`PairingView.qml`, `MicdroidPopup.qml`, etc. are the literal same files the plasmoid uses,
unmodified — see [`micdroid_tray/bridge.py`](micdroid_tray/bridge.py)'s module docstring
for how that's possible (short version: the bridge exposes the same property/method
surface the plasmoid's `main.qml` `root` object does, so those views can't tell the
difference).

## Requirements

- Everything the [main README](../README.md) lists (adb, scrcpy, PipeWire tools) — same
  daemon, same requirements.
- PySide6. On Arch: `sudo pacman -S python-pyside6`. Other distros: your equivalent
  package, or `pip install PySide6`.

## Install

```bash
./install.sh
```

Installs an application-launcher entry and an autostart entry (so it starts quietly in
the tray on login, like Discord/Steam do — remove that from System Settings → Autostart
any time if you'd rather launch it manually).

## Run without installing

```bash
python3 -m micdroid_tray.main
```

## What's here

- `micdroid_tray/bridge.py` — `DaemonBridge`, a `QObject` wrapping `PySide6.QtDBus` calls/
  signals to the daemon, exposed to QML as the `bridge` context property.
- `micdroid_tray/devices_model.py` — `QAbstractListModel` backing the device list, role-
  compatible with the plasmoid's plain QML `ListModel`.
- `micdroid_tray/main.py` — entry point: `QApplication`, the `QSystemTrayIcon` (left-click
  toggles the window, right-click opens the menu — mute toggle, disconnect active device,
  settings, quit), and the `QQmlApplicationEngine` hosting the QML below.
- `qml/Main.qml` — the window, hosting the shared `MicdroidPopup.qml` content.
- `qml/SettingsWindow.qml` — the one piece of UI that *isn't* shared with the plasmoid
  (its config page uses kcfg, which doesn't apply here) — same fields, bound directly to
  `bridge` properties instead.
- `qml/views` — symlink to `../package/contents/ui/views`.

## Known trade-offs (v1)

- Daemon calls block the UI thread briefly (QtDBus calls are synchronous here) — every
  local call measured under ~50ms in practice, so this is imperceptible except for
  `restartService`/`bootstrap`, which can take a few seconds (the daemon's own
  `wait_for_name_owned` polling) and will briefly freeze the window during that specific
  action. A background-thread version is a reasonable fast-follow if that ever feels
  sluggish.
- The tray icon only has a static "muted" badge (a red dot composited on top) rather than
  the plasmoid panel icon's animated connection-state indicators — `QSystemTrayIcon` is a
  single static `QIcon`, not a live QML surface.
