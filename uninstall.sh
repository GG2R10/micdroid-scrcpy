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

echo "==> Done. Your paired-device roster and settings (~/.config/micdroid/) were left untouched."
