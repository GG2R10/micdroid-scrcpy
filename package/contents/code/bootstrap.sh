#!/bin/bash
# First-run backend setup: creates the daemon's venv, installs the bundled
# micdroid_daemon package into it, and installs the systemd --user unit -
# entirely from files shipped inside *this same installed plasmoid package*
# (contents/daemon/), not the git repo's root-level install.sh.
#
# This is what makes installing purely through the KDE Store work end to
# end: the Store only ever distributes contents/ (a .plasmoid archive is
# literally a zip of it), so a plain `kpackagetool6 -i` or a Store install
# would otherwise leave the widget with no daemon at all - permanently
# "Service unavailable", no way to recover from inside the widget itself.
# Bundling the daemon source under contents/daemon/ and having the widget
# provision it on first run closes that gap.
#
# Cheap to call on every `servicectl.sh ensure-running` (i.e. every widget
# load): the up-to-date check below is just a file check plus a small
# `python3 -c` reading metadata.json, not a real re-install, unless the
# bundled package version actually changed since the last successful run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DAEMON_SRC="$PACKAGE_ROOT/contents/daemon"
METADATA="$PACKAGE_ROOT/metadata.json"

INSTALL_DIR="$HOME/.local/share/micdroid"
VENV_DIR="$INSTALL_DIR/venv"
VERSION_FILE="$INSTALL_DIR/.installed_version"
UNIT_DEST="$HOME/.config/systemd/user/micdroid.service"

package_version() {
    python3 -c "import json; print(json.load(open('$METADATA'))['KPlugin']['Version'])" 2>/dev/null || echo "unknown"
}

VERSION="$(package_version)"

if [ -x "$VENV_DIR/bin/python" ] && [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ]; then
    exit 0
fi

echo "Setting up the micdroid backend ($VERSION) - first run, or an update; this needs network access once to fetch a couple of small Python packages." >&2

mkdir -p "$INSTALL_DIR"
if [ ! -x "$VENV_DIR/bin/python" ]; then
    python3 -m venv "$VENV_DIR" \
        || { echo "failed to create the Python venv - is python3-venv (or your distro's equivalent) installed?" >&2; exit 1; }
fi

"$VENV_DIR/bin/pip" install --upgrade pip -q
"$VENV_DIR/bin/pip" install -q "$DAEMON_SRC" \
    || { echo "failed to install the daemon into its venv - check network access" >&2; exit 1; }

mkdir -p "$(dirname "$UNIT_DEST")"
cp "$DAEMON_SRC/systemd/micdroid.service" "$UNIT_DEST"
systemctl --user daemon-reload

echo "$VERSION" > "$VERSION_FILE"
echo "backend set up ($VERSION)" >&2
