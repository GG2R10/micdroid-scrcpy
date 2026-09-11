#!/bin/bash
# Installs/upgrades just the Plasma widget frontend. Runs the same
# contents/code/bootstrap.sh the widget itself runs on first load (works
# identically whether it's called from here or from the installed plasmoid -
# it resolves its own paths relative to itself), then installs/upgrades the
# Plasma widget itself. No separate build system, matching the sibling
# gamemode-status project's precedent.
#
# Most people should run ../install.sh instead (it offers this, the tray
# app, or both) - this one's here for anyone who wants just the widget
# without the interactive menu, or for scripts/docs that call it directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="com.github.GG2R10.micdroid"

echo "==> Setting up the backend (venv + systemd unit)"
bash "$SCRIPT_DIR/contents/code/bootstrap.sh"

echo "==> Installing the Plasma widget"
if kpackagetool6 -t Plasma/Applet -s "$PLUGIN_ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$SCRIPT_DIR"
else
    kpackagetool6 -t Plasma/Applet -i "$SCRIPT_DIR"
fi

cat <<'EOF'

==> Done.

Next steps:
  1. Add the "Micdroid" widget to a panel or the desktop - it starts its
     own backend service on first load.
  2. If you haven't already, pair your phone once from a terminal:
         adb pair <phone-ip>:<pairing-port>
     then use the widget's "Pair new device" (or "Connect by address" with
     <phone-ip>:<port> from Settings > Developer options > Wireless
     debugging) to finish connecting it.

Logs:  journalctl --user -u micdroid.service -f
EOF
