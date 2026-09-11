#!/bin/bash
# Installs the Micdroid tray app: no venv/pip step (unlike ../install.sh for
# the daemon) - this runs against the system Python + system PySide6
# directly, since there's no `pip` on a plain Arch install (PySide6 comes
# from the `python-pyside6` pacman package instead, confirmed already
# present on this machine) and PySide6 wheels are large enough that
# reinstalling them into a private venv would be wasteful when the system
# copy works fine. Other distros: `pip install PySide6` into a venv would
# also work, just point the .desktop file's Exec at that venv's python3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$HOME/.local/share/applications"
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="micdroid-tray.desktop"

if ! python3 -c "import PySide6" 2>/dev/null; then
    echo "PySide6 not found for $(command -v python3)." >&2
    echo "Install it first - on Arch: sudo pacman -S python-pyside6" >&2
    echo "On other distros: pip install --user PySide6 (or your distro's equivalent package)." >&2
    exit 1
fi

# The daemon itself (../package/contents/daemon/, ../package/contents/code/
# servicectl.sh) is required the same way it is for the plasmoid - this app
# is just an alternative frontend to the exact same D-Bus service, not a
# reimplementation. Running the plasmoid's own bootstrap.sh here (rather
# than duplicating its version-check/venv-creation logic) means either
# frontend can independently make sure the daemon is actually installed.
bash "$SCRIPT_DIR/../package/contents/code/bootstrap.sh" \
    || { echo "backend setup failed - see stderr above" >&2; exit 1; }

mkdir -p "$DESKTOP_DIR" "$AUTOSTART_DIR"

cat > "$DESKTOP_DIR/$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Micdroid
Comment=Use your Android phone's microphone as a PC microphone (tray app)
Exec=python3 -m micdroid_tray.main
Path=$SCRIPT_DIR
Icon=$SCRIPT_DIR/../assets/micdroid_icon_512.png
Terminal=false
Categories=AudioVideo;Audio;
X-KDE-StartupNotify=false
EOF

# Discord/Steam-style: starts quietly in the tray on login. Easy to turn
# off from KDE's own System Settings -> Autostart if unwanted - this is
# just seeding that list, not something hidden from the user afterwards.
cp "$DESKTOP_DIR/$DESKTOP_FILE" "$AUTOSTART_DIR/$DESKTOP_FILE"

echo "Installed. Launch now with: python3 -m micdroid_tray.main (from $SCRIPT_DIR)"
echo "Also added to your application launcher and set to start at login"
echo "(remove the login part any time from System Settings -> Autostart)."
