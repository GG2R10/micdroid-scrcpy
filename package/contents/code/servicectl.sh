#!/bin/bash
# Manage the micdroid daemon's systemd --user unit. Invoked from main.qml's
# `control` Plasma5Support.DataSource, same shape as gamemode-status's
# control.sh: exit 0 + stdout on success, nonzero + stderr on failure.
set -euo pipefail

UNIT="micdroid.service"
BUS_NAME="org.micdroid.Daemon1"

# systemctl reporting "started"/"restarted" only means systemd handed the
# process off - the Python daemon still needs a moment to import, connect to
# the session bus, and call request_name() before the D-Bus name is actually
# owned. Without waiting for that, main.qml's bootstrap() fires its first
# gdbus calls immediately after this script returns and hits
# "GDBus.Error:...ServiceUnknown: The name is not activatable" (confirmed
# live: this raced badly enough that repeated user clicks on the resulting
# error each restarted the daemon again, which also drops any wireless adb
# connections - restarting the adb *server*, something this daemon does
# itself whenever its own track-devices socket can't reach it, terminates
# all existing TCP/IP adb sessions; USB devices just get rediscovered but
# wireless ones don't reconnect on their own).
wait_for_name_owned() {
    for _ in $(seq 1 30); do
        if gdbus call --session --dest org.freedesktop.DBus \
                --object-path /org/freedesktop/DBus \
                --method org.freedesktop.DBus.NameHasOwner "$BUS_NAME" 2>/dev/null \
                | grep -q "true"; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

case "${1:-}" in
    ensure-running)
        if systemctl --user is-active --quiet "$UNIT" && wait_for_name_owned; then
            echo "already running"
        else
            systemctl --user start "$UNIT" \
                || { echo "failed to start $UNIT - is it installed? run install.sh" >&2; exit 1; }
            wait_for_name_owned \
                || { echo "$UNIT started but never claimed $BUS_NAME - check journalctl --user -u $UNIT" >&2; exit 1; }
            echo "started"
        fi
        ;;
    restart)
        systemctl --user restart "$UNIT" \
            || { echo "failed to restart $UNIT" >&2; exit 1; }
        wait_for_name_owned \
            || { echo "$UNIT restarted but never claimed $BUS_NAME - check journalctl --user -u $UNIT" >&2; exit 1; }
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
