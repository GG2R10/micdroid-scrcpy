#!/bin/bash
# Reverses install.sh.
set -euo pipefail

INSTALL_DIR="$HOME/.local/share/micdroid"
UNIT_DEST="$HOME/.config/systemd/user/micdroid.service"

echo "==> Stopping and disabling the service"
systemctl --user stop micdroid.service 2>/dev/null || true
systemctl --user disable micdroid.service 2>/dev/null || true

echo "==> Removing the systemd unit"
rm -f "$UNIT_DEST"
systemctl --user daemon-reload

echo "==> Removing the Plasma widget"
kpackagetool6 -t Plasma/Applet -r com.github.GG2R10.micdroid 2>/dev/null || true

echo "==> Removing $INSTALL_DIR"
rm -rf "$INSTALL_DIR"

# The tray app has no venv/systemd footprint of its own (see tray-app/
# install.sh) - just these two launcher entries, removed here too so this
# script is the one place that reverses whatever ./install.sh did,
# regardless of which frontend(s) were actually installed.
TRAY_DESKTOP="$HOME/.local/share/applications/micdroid-tray.desktop"
TRAY_AUTOSTART="$HOME/.config/autostart/micdroid-tray.desktop"
if [ -f "$TRAY_DESKTOP" ] || [ -f "$TRAY_AUTOSTART" ]; then
    echo "==> Removing the tray app's launcher/autostart entries"
    rm -f "$TRAY_DESKTOP" "$TRAY_AUTOSTART"
fi

echo "==> Done. Your paired-device roster and settings (~/.config/micdroid/) were left untouched."
