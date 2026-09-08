#!/bin/bash
# Manage the micdroid daemon's systemd --user unit. Invoked from main.qml's
# `control` Plasma5Support.DataSource, same shape as gamemode-status's
# control.sh: exit 0 + stdout on success, nonzero + stderr on failure.
set -euo pipefail

UNIT="micdroid.service"

case "${1:-}" in
    ensure-running)
        if systemctl --user is-active --quiet "$UNIT"; then
            echo "already running"
        else
            systemctl --user start "$UNIT" \
                || { echo "failed to start $UNIT - is it installed? run install.sh" >&2; exit 1; }
            echo "started"
        fi
        ;;
    restart)
        systemctl --user restart "$UNIT" \
            || { echo "failed to restart $UNIT" >&2; exit 1; }
        echo "restarted"
        ;;
    status)
        if systemctl --user is-active --quiet "$UNIT"; then
            echo "active"
        else
            echo "inactive"
            exit 1
        fi
        ;;
    *)
        echo "usage: servicectl.sh {ensure-running|restart|status}" >&2
        exit 2
        ;;
esac
