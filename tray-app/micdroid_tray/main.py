"""Entry point for the Micdroid tray app - the Qt/system-tray counterpart to
the KDE Plasma widget (../../package/), talking to the exact same daemon
over the exact same D-Bus interface (see bridge.py's module docstring for
why plain QtDBus, not the daemon's own dbus-next, is used here).

Run directly with the system Python + system PySide6 (see ../README.md for
why there's no venv/pip step here, unlike the daemon's install.sh):

    python3 -m micdroid_tray.main
"""

from __future__ import annotations

import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QAction, QColor, QIcon, QPainter, QPixmap
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlEngine
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from .bridge import DaemonBridge

_TRAY_APP_DIR = Path(__file__).resolve().parent.parent
_QML_DIR = _TRAY_APP_DIR / "qml"

# The shared views (qml/views/, symlinked to ../../package/contents/ui/
# views/) call the bare global `i18n(...)` throughout, same as main.qml and
# this app's own Main.qml/SettingsWindow.qml - confirmed live (via two
# screenshots the user took: button/label text rendering as entirely
# blank, while literal, non-i18n()-wrapped strings like PairingView.qml's
# "192.168.1.42" placeholder rendered fine) that a plain
# QQmlApplicationEngine has no such function at all. Inside plasmashell,
# `i18n` is injected automatically by Plasma/KDeclarative's own QML
# environment setup - a standalone PySide6 engine gets none of that, so
# every `i18n("...")` call was silently evaluating to `undefined`
# (QML doesn't throw on a call to a genuinely undefined bare identifier in
# a binding - the property just ends up empty). Registering a shim
# function as a real global (via QJSEngine.globalObject(), not a context
# property - a context property would only be reachable as a *named*
# object, not as a bare callable identifier) fixes every call site at once
# without touching the shared QML - real translation support (.po files,
# KI18n) is out of scope here since the plasmoid doesn't have any either.
_I18N_SHIM_JS = """
(function() {
    function subst(str, args) {
        var s = String(str);
        for (var i = 0; i < args.length; i++) {
            s = s.split("%" + (i + 1)).join(String(args[i]));
        }
        return s;
    }
    return function() {
        var args = Array.prototype.slice.call(arguments);
        var str = args.shift();
        return subst(str, args);
    };
})()
"""
_ICON_PATH = _TRAY_APP_DIR.parent / "assets" / "micdroid_icon_512.png"


def _muted_icon(base: QIcon) -> QIcon:
    """Composites a small red dot onto the base icon's bottom-right corner -
    the tray-icon equivalent of CompactView.qml's static red tint when
    muted, since QSystemTrayIcon has no room for a live QML-driven
    indicator, just a QIcon.
    """
    pixmap = base.pixmap(64, 64)
    result = QPixmap(pixmap)
    painter = QPainter(result)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(QColor("#e74c3c"))
    painter.setPen(QColor("#2b2b2b"))
    size = pixmap.width() * 0.42
    painter.drawEllipse(pixmap.width() - size, pixmap.height() - size, size, size)
    painter.end()
    return QIcon(result)


class TrayApp:
    def __init__(self) -> None:
        self.app = QApplication(sys.argv)
        self.app.setQuitOnLastWindowClosed(False)  # closing the main window hides it, doesn't quit - see Main.qml
        self.app.setApplicationName("Micdroid")
        self.app.setOrganizationName("micdroid")

        self.bridge = DaemonBridge()

        self.engine = QQmlApplicationEngine()
        self.engine.rootContext().setContextProperty("bridge", self.bridge)
        # Must happen before loading any QML - see _I18N_SHIM_JS's comment
        # above for why this is needed at all.
        i18n_fn = self.engine.evaluate(_I18N_SHIM_JS)
        self.engine.globalObject().setProperty("i18n", i18n_fn)
        self.engine.load(QUrl.fromLocalFile(str(_QML_DIR / "Main.qml")))
        if not self.engine.rootObjects():
            raise RuntimeError("Main.qml failed to load - see stderr above for the QML error")
        self.main_window = self.engine.rootObjects()[0]
        # Settings and Quit are reachable only from the tray menu below
        # (_build_menu()'s settings_action/quit_action) - deliberately not
        # duplicated as buttons in Main.qml, to keep that window's look as
        # close as possible to the plasmoid's popup.

        self._settings_window = None  # lazily created, see _show_settings()
        self._settings_component = None  # must stay referenced too - see _show_settings()

        self._base_icon = QIcon(str(_ICON_PATH))
        self._muted_icon = _muted_icon(self._base_icon)
        self.tray = QSystemTrayIcon(self._base_icon)
        self.tray.setToolTip("Micdroid")
        self._build_menu()
        self.tray.activated.connect(self._on_tray_activated)
        self.tray.show()

        self.bridge.mutedChanged.connect(self._update_icon)
        self.bridge.activeDeviceChanged.connect(self._update_disconnect_action)
        self._update_icon()
        self._update_disconnect_action()

    # --- tray menu ------------------------------------------------------

    def _build_menu(self) -> None:
        menu = QMenu()

        self.toggle_window_action = QAction("Mostrar/Ocultar")
        self.toggle_window_action.triggered.connect(self._toggle_window)
        menu.addAction(self.toggle_window_action)

        self.mute_action = QAction("Silenciar micrófono")
        self.mute_action.triggered.connect(lambda: self.bridge.toggleMute())
        menu.addAction(self.mute_action)

        self.disconnect_action = QAction("Desconectar dispositivo activo")
        self.disconnect_action.triggered.connect(
            lambda: self.bridge.activeDevice and self.bridge.disconnectDevice(self.bridge.activeDevice)
        )
        menu.addAction(self.disconnect_action)

        menu.addSeparator()

        settings_action = QAction("Configuración…")
        settings_action.triggered.connect(self._show_settings)
        menu.addAction(settings_action)

        menu.addSeparator()

        quit_action = QAction("Salir")
        quit_action.triggered.connect(self._quit)
        menu.addAction(quit_action)

        self.tray.setContextMenu(menu)

    def _update_icon(self) -> None:
        self.tray.setIcon(self._muted_icon if self.bridge.muted else self._base_icon)
        self.mute_action.setText("Activar micrófono" if self.bridge.muted else "Silenciar micrófono")

    def _update_disconnect_action(self) -> None:
        self.disconnect_action.setEnabled(bool(self.bridge.activeDevice))

    def _on_tray_activated(self, reason) -> None:
        # Trigger == a plain left click (the enum's actual name on Linux/X11
        # SNI backends too, despite "Trigger" sounding X11Embed-specific) -
        # matches the Discord/Steam convention of left-click toggling the
        # window, right-click opening the menu (handled automatically by
        # setContextMenu() above, no extra wiring needed for that part).
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self._toggle_window()

    def _toggle_window(self) -> None:
        if self.main_window.isVisible():
            self.main_window.hide()
        else:
            self.main_window.show()
            self.main_window.raise_()
            self.main_window.requestActivate()

    def _quit(self) -> None:
        # Per the user's explicit request: this app should quit like a
        # normal self-contained program, not leave the daemon running
        # headless in the background just because the tray icon is gone -
        # unlike the plasmoid, which manages the same systemd unit
        # independently of its own widget lifecycle and is expected to
        # keep the daemon running across a panel/widget restart. If both
        # frontends are ever run at once, quitting this one does stop the
        # daemon out from under the plasmoid too - an accepted trade-off
        # for "quitting this app means it's actually gone", not a bug.
        self.bridge.stopService()
        self.app.quit()

    def _show_settings(self) -> None:
        if self._settings_window is None:
            # Keep the QQmlComponent itself alive too (self._settings_component,
            # not just a local var) - confirmed live this was the actual bug the
            # user hit: an object created via QQmlComponent.create() defaults to
            # JavaScript ownership (per Qt/QML's own rules for dynamically
            # created objects), so it gets garbage-collected by the QML engine
            # almost immediately regardless of the Python-side reference in
            # self._settings_window - "Configuración..." opened nothing,
            # silently, because the window was already destroyed by the time
            # .show() ran. QQmlEngine.setObjectOwnership(..., CppOwnership)
            # below is the documented fix: it tells the engine Python/C++ owns
            # this object's lifetime, not QML's JS garbage collector.
            self._settings_component = QQmlComponent(
                self.engine, QUrl.fromLocalFile(str(_QML_DIR / "SettingsWindow.qml"))
            )
            self._settings_window = self._settings_component.create()
            if self._settings_window is None:
                # Surface the QML error instead of silently doing nothing -
                # component.errorString() is the actual reason (e.g. a typo
                # in a property binding), not just "it didn't work".
                raise RuntimeError(f"SettingsWindow.qml failed to load: {self._settings_component.errorString()}")
            QQmlEngine.setObjectOwnership(self._settings_window, QQmlEngine.CppOwnership)
        self._settings_window.show()
        self._settings_window.raise_()
        self._settings_window.requestActivate()

    def run(self) -> int:
        return self.app.exec()


def main() -> int:
    return TrayApp().run()


if __name__ == "__main__":
    sys.exit(main())
