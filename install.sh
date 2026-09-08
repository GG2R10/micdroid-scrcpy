#!/bin/bash
# Installs the micdroid daemon (as a systemd --user service) and the KDE
# Plasma widget. No build system, matching the sibling gamemode-status
# project's precedent - this is a plain install script, not a packaging tool.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_SRC="$SCRIPT_DIR/daemon"
INSTALL_DIR="$HOME/.local/share/micdroid"
VENV_DIR="$INSTALL_DIR/venv"
UNIT_SRC="$DAEMON_SRC/systemd/micdroid.service"
UNIT_DEST="$HOME/.config/systemd/user/micdroid.service"

echo "==> Setting up the daemon virtualenv at $VENV_DIR"
mkdir -p "$INSTALL_DIR"
if [ ! -x "$VENV_DIR/bin/python" ]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --upgrade pip -q
"$VENV_DIR/bin/pip" install -q "$DAEMON_SRC"

echo "==> Installing the systemd --user unit"
mkdir -p "$(dirname "$UNIT_DEST")"
cp "$UNIT_SRC" "$UNIT_DEST"
systemctl --user daemon-reload

echo "==> Installing the Plasma widget"
if kpackagetool6 -t Plasma/Applet -s com.micdroid.applet >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$SCRIPT_DIR/package/"
else
    kpackagetool6 -t Plasma/Applet -i "$SCRIPT_DIR/package/"
fi

cat <<'EOF'

==> Done.

Next steps:
  1. Start the service:      systemctl --user start micdroid.service
     (or just add the widget to a panel - it starts the service itself)
  2. Add the "Micdroid" widget to a panel or the desktop.
  3. If you haven't already, pair your phone once from a terminal:
         adb pair <phone-ip>:<pairing-port>
     then use the widget's "Connect" field with <phone-ip>:<port> from
     `adb connect` (Settings > Developer options > Wireless debugging).

Logs:  journalctl --user -u micdroid.service -f
EOF
