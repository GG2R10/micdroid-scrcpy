#!/bin/bash
# Thin `gdbus call` wrapper against the micdroid daemon's own D-Bus service.
# Usage: daemonctl.sh <MethodName> [gdbus-formatted arg]...
# Each remaining arg is passed to `gdbus call` verbatim as one positional
# method argument, so callers (main.qml) are responsible for GVariant-literal
# quoting (e.g. "'192.168.1.18:5555'" for a string, "{'k': <'v'>}" for SetConfig's
# a{sv} dict).
set -euo pipefail

method="${1:?usage: daemonctl.sh <MethodName> [args...]}"
shift

exec gdbus call --session \
    --dest org.micdroid.Daemon1 \
    --object-path /org/micdroid/Daemon \
    --method "org.micdroid.Daemon1.$method" \
    "$@"
