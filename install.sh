#!/bin/bash
# Single entry point for both frontends - delegates to package/install.sh
# (the Plasma widget) and/or tray-app/install.sh (the system-tray app)
# rather than duplicating either one's logic. Both of those already call
# package/contents/code/bootstrap.sh independently to set up the shared
# daemon, so running either or both in any order is safe - the daemon only
# actually gets (re)installed once regardless (see bootstrap.sh's own
# version-check skip logic).
#
# Run non-interactively with an argument if you already know what you
# want, e.g. from a script: ./install.sh widget | tray | both
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_widget() { bash "$SCRIPT_DIR/package/install.sh"; }
install_tray() { bash "$SCRIPT_DIR/tray-app/install.sh"; }

choice="${1:-}"
if [ -z "$choice" ]; then
    cat <<'EOF'
Micdroid - which frontend do you want to install?

  1) KDE Plasma widget       - a panel/desktop widget (needs Plasma 6)
  2) System tray app         - a standalone Qt app, tray icon like Discord/Steam
  3) Both
  4) Cancel

Either way, this sets up the same shared background service - installing
both is safe and doesn't duplicate anything.
EOF
    read -rp "> " reply
    case "$reply" in
        1|widget) choice="widget" ;;
        2|tray) choice="tray" ;;
        3|both) choice="both" ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

case "$choice" in
    widget) install_widget ;;
    tray) install_tray ;;
    both) install_widget; echo; install_tray ;;
    *) echo "usage: $0 [widget|tray|both]" >&2; exit 2 ;;
esac
