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

REPO_URL="https://github.com/GG2R10/micdroid-scrcpy.git"
CLONE_DIR="${MICDROID_SRC_DIR:-$HOME/.local/share/micdroid-scrcpy}"

# Support `curl -fsSL .../install.sh | bash` directly, with no git checkout
# on disk at all yet: a script read from a pipe has no meaningful
# ${BASH_SOURCE[0]} (and even a real path wouldn't have package/tray-app
# sitting next to it in that case). Detect that and clone first, to a
# *permanent* location, not a temp dir - installed launchers (the tray
# app's .desktop Path=, the widget's own bootstrap.sh calls) all point back
# at this checkout afterwards, so it has to keep existing. Re-running the
# same one-liner later just updates it in place instead of re-cloning.
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
if [ -z "$_here" ] || [ ! -f "$_here/package/install.sh" ]; then
    command -v git >/dev/null 2>&1 || { echo "git is required - install it first" >&2; exit 1; }
    if [ -d "$CLONE_DIR/.git" ]; then
        echo "==> Updating existing checkout at $CLONE_DIR"
        git -C "$CLONE_DIR" pull --ff-only
    else
        echo "==> Cloning micdroid-scrcpy to $CLONE_DIR"
        git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
    fi
    exec bash "$CLONE_DIR/install.sh" "$@"
fi
SCRIPT_DIR="$_here"

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
    # < /dev/tty, not plain stdin: when this runs via `curl ... | bash`,
    # stdin is the pipe from curl (already at EOF by the time we get here) -
    # reading the terminal directly instead is the standard workaround, and
    # works identically for a normal (non-piped) run too.
    read -rp "> " reply < /dev/tty
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
