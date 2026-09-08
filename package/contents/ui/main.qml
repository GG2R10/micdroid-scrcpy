import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import "views" as Views

PlasmoidItem {
    id: root

    property bool serviceRunning: false
    property bool dependenciesOk: false
    property var dependencyResults: ({})
    property string activeDevice: ""
    property string forwardingState: "Disconnected"
    property string lastError: ""
    property bool muted: false
    property alias devicesModel: devicesModel

    readonly property var requiredTools: ["adb", "scrcpy", "pw-loopback", "pactl"]

    ListModel { id: devicesModel }

    // --- helpers ---------------------------------------------------

    function codePath(file) {
        return Qt.resolvedUrl("../code/" + file).toString().replace(/^file:\/\//, "")
    }

    function shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // gdbus's GVariant text output for a bare string return is `('...',)`.
    // Strip that shell, un-escape GVariant's `\'`/`\\` escaping, JSON.parse.
    function parseGdbusJsonString(stdout) {
        const m = /^\(\s*'([\s\S]*)'\s*,?\s*\)\s*$/.exec(stdout.trim())
        if (!m) return null
        const unescaped = m[1].replace(/\\'/g, "'").replace(/\\\\/g, "\\")
        try {
            return JSON.parse(unescaped)
        } catch (e) {
            console.warn("micdroid: could not parse daemon JSON response:", e, unescaped)
            return null
        }
    }

    // Parses simple `(true, 'message')`-shaped gdbus tuples (bool/string only
    // - good enough for the action methods, which never return containers).
    function parseGdbusTuple(stdout) {
        const body = stdout.trim().replace(/^\(/, "").replace(/\)\s*$/, "")
        const parts = []
        let cur = "", inStr = false
        for (let i = 0; i < body.length; i++) {
            const c = body[i]
            if (inStr) {
                if (c === "\\" && i + 1 < body.length) { cur += body[i + 1]; i++; continue }
                if (c === "'") { inStr = false; continue }
                cur += c
            } else {
                if (c === "'") { inStr = true; continue }
                if (c === ",") { parts.push(cur.trim()); cur = ""; continue }
                cur += c
            }
        }
        if (cur.trim().length) parts.push(cur.trim())
        return parts.map(p => p === "true" ? true : p === "false" ? false : p)
    }

    function configToGVariant(cfg) {
        const parts = []
        for (const k in cfg) {
            const v = cfg[k]
            let variant
            if (typeof v === "boolean") variant = v ? "true" : "false"
            else if (typeof v === "number") variant = String(v)
            else if (Array.isArray(v)) variant = "[" + v.map(n => String(n)).join(",") + "]"
            else variant = "'" + String(v).replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'"
            parts.push("'" + k + "': <" + variant + ">")
        }
        return "{" + parts.join(", ") + "}"
    }

    // --- D-Bus action/query plumbing ---------------------------------

    Plasma5Support.DataSource {
        id: control
        engine: "executable"
        // Keyed by the exact command string (== the `source` onNewData gets),
        // since several commands can be in flight at once (bootstrap() fires
        // pushConfig/refreshDevices/refreshStatus back to back) and each
        // connectSource() call is its own independent source, not a single
        // request/response slot.
        property var _callbacks: ({})

        function run(cmd, onDone) {
            control._callbacks[cmd] = onDone || null
            control.connectSource(cmd)
        }

        onNewData: (source, data) => {
            // Plasma5Support's "executable" engine uses "exit code" (with a
            // space), not "exitcode" - confirmed empirically via plasmawindowed
            // (data keys logged: exit code/exit status/stdout/stderr).
            const exitCode = data["exit code"]
            const stdout = (data["stdout"] || "").toString()
            const stderr = (data["stderr"] || "").toString()
            control.disconnectSource(source)
            root.lastError = (exitCode !== 0) ? (stderr.trim() || ("command failed: " + source)) : ""
            const cb = control._callbacks[source]
            delete control._callbacks[source]
            if (cb) cb(exitCode === 0, stdout, stderr)
        }
    }

    // Self-re-arming tail of the daemon's runtime event log - see
    // micdroid_daemon/eventlog.py for why this is used instead of `gdbus
    // monitor` directly (gap-free: only a file position is tracked, no D-Bus
    // subscription is torn down/recreated per event).
    Plasma5Support.DataSource {
        id: eventStream
        engine: "executable"

        function arm() {
            Qt.callLater(function () {
                eventStream.connectSource(
                    "bash -c 'tail -F -n0 \"${XDG_RUNTIME_DIR:-/tmp}/micdroid/events.log\" 2>/dev/null | head -n1'"
                )
            })
        }

        onNewData: (source, data) => {
            eventStream.disconnectSource(source)
            const line = (data["stdout"] || "").toString().trim()
            if (line.length) root.handleEvent(line)
            eventStream.arm()
        }
    }

    function handleEvent(line) {
        let evt
        try { evt = JSON.parse(line) } catch (e) { return }
        const args = evt.args || []
        switch (evt.signal) {
        case "DeviceAdded":
            upsertDevice(args[0])
            break
        case "DeviceRemoved":
            removeDevice(args[0])
            break
        case "DeviceStateChanged":
            updateDeviceField(args[0], "state", args[1])
            break
        case "ForwardingStateChanged":
            updateDeviceField(args[0], "forwardingState", args[1])
            if (["Forwarding", "DegradedProbing", "Reconnecting", "NeedsRepair"].includes(args[1])) {
                root.activeDevice = args[0]
                root.forwardingState = args[1]
            } else if (root.activeDevice === args[0]) {
                root.activeDevice = ""
                root.forwardingState = args[1]
            }
            break
        case "ErrorOccurred":
            root.lastError = args[2] || ""
            break
        case "DependencyCheckResult":
            applyDependencyResults(args[0] || {})
            break
        }
    }

    function applyDependencyResults(results) {
        root.dependencyResults = results
        root.dependenciesOk = requiredTools.every(t => !!results[t])
    }

    function upsertDevice(dev) {
        for (let i = 0; i < devicesModel.count; i++) {
            if (devicesModel.get(i).serial === dev.serial) { devicesModel.set(i, dev); return }
        }
        devicesModel.append(dev)
    }

    function removeDevice(serial) {
        for (let i = 0; i < devicesModel.count; i++) {
            if (devicesModel.get(i).serial === serial) { devicesModel.remove(i); return }
        }
    }

    function updateDeviceField(serial, field, value) {
        for (let i = 0; i < devicesModel.count; i++) {
            if (devicesModel.get(i).serial === serial) { devicesModel.setProperty(i, field, value); return }
        }
    }

    // --- one-shot queries ---------------------------------------------

    function refreshDevices() {
        control.run(codePath("daemonctl.sh") + " ListDevices", function (ok, stdout) {
            if (!ok) return
            const list = parseGdbusJsonString(stdout)
            if (!list) return
            devicesModel.clear()
            for (const dev of list) {
                devicesModel.append(dev)
                if (["Forwarding", "DegradedProbing", "Reconnecting", "NeedsRepair"].includes(dev.forwardingState)) {
                    root.activeDevice = dev.serial
                    root.forwardingState = dev.forwardingState
                }
            }
        })
    }

    function refreshStatus() {
        control.run(codePath("daemonctl.sh") + " GetStatus", function (ok, stdout) {
            if (!ok) return
            const status = parseGdbusJsonString(stdout)
            if (!status) return
            if (status.dependencyResults) applyDependencyResults(status.dependencyResults)
            root.activeDevice = status.activeDevice || ""
            root.forwardingState = status.forwardingState || "Disconnected"
        })
    }

    function refreshMuteState() {
        control.run(codePath("daemonctl.sh") + " GetMuted", function (ok, stdout) {
            if (!ok) return
            const parts = parseGdbusTuple(stdout)
            root.muted = !!parts[0]
        })
    }

    // --- commands -------------------------------------------------

    function toggleMute(onDone) {
        control.run(codePath("daemonctl.sh") + " ToggleMute", function (ok, stdout) {
            if (ok) {
                const parts = parseGdbusTuple(stdout)
                if (parts[0]) root.muted = !!parts[1]
            }
            if (onDone) onDone(root.muted)
        })
    }

    function startForwarding(serial) {
        control.run(codePath("daemonctl.sh") + " StartForwarding " + shQuote(serial))
    }

    function stopForwarding(serial) {
        control.run(codePath("daemonctl.sh") + " StopForwarding " + shQuote(serial))
    }

    function disconnectDevice(serial, onDone) {
        control.run(codePath("daemonctl.sh") + " Disconnect " + shQuote(serial), function (ok, stdout) {
            if (ok) {
                const parts = parseGdbusTuple(stdout)
                updateDeviceField(serial, "forwardingState", "Disconnected")
                if (onDone) onDone(!!parts[0])
                return
            }
            if (onDone) onDone(false)
        })
    }

    function connectByAddress(address, onDone) {
        control.run(codePath("daemonctl.sh") + " ConnectByAddress " + shQuote(address), function (ok, stdout) {
            if (ok) refreshDevices()
            if (onDone) onDone(ok)
        })
    }

    function pairDevice(host, pairPort, code, onDone) {
        const cmd = codePath("daemonctl.sh") + " Pair "
            + shQuote(host) + " " + shQuote(pairPort) + " " + shQuote(code)
        control.run(cmd, function (ok, stdout) {
            let paired = false, connected = false, message = ""
            if (ok) {
                const parts = parseGdbusTuple(stdout)
                paired = !!parts[0]
                connected = !!parts[1]
                message = parts[2] || ""
                if (connected) refreshDevices()
            } else {
                message = root.lastError
            }
            if (onDone) onDone(paired, connected, message)
        })
    }

    function retryDevice(serial) {
        control.run(codePath("daemonctl.sh") + " Connect " + shQuote(serial))
    }

    function forgetDevice(serial) {
        control.run(codePath("daemonctl.sh") + " Forget " + shQuote(serial), function (ok) {
            if (ok) removeDevice(serial)
        })
    }

    function rescanDependencies() {
        control.run(codePath("daemonctl.sh") + " RescanDependencies", function (ok, stdout) {
            const results = parseGdbusJsonString(stdout)
            if (results) applyDependencyResults(results)
        })
    }

    function restartService(onDone) {
        // servicectl.sh now polls for the D-Bus name to actually be owned
        // again before returning, so this can take a few seconds - callers
        // should show a busy state rather than let it look unresponsive
        // (confirmed live: without one, repeated impatient clicks each
        // restarted the daemon again, and every such restart drops all
        // wireless adb connections along with it).
        control.run(codePath("servicectl.sh") + " restart", function (ok) {
            root.serviceRunning = ok
            if (ok) bootstrap()
            if (onDone) onDone(ok)
        })
    }

    function stopService(onDone) {
        control.run(codePath("servicectl.sh") + " stop", function (ok) {
            if (ok) {
                root.serviceRunning = false
                notifyClient(i18n("Micdroid service stopped"))
            }
            if (onDone) onDone(ok)
        })
    }

    // Used by the right-click quick action - starts vs stops depending on
    // the last known state, since there's no popup open to show a
    // start/stop choice.
    function toggleService(onDone) {
        if (root.serviceRunning) {
            stopService(onDone)
        } else {
            control.run(codePath("servicectl.sh") + " ensure-running", function (ok) {
                root.serviceRunning = ok
                if (ok) {
                    bootstrap()
                    notifyClient(i18n("Micdroid service started"))
                }
                if (onDone) onDone(ok)
            })
        }
    }

    // Fire-and-forget client-side notification for the right-click quick
    // actions - these run with no popup open, so without this there would
    // be no feedback at all that anything happened. Daemon-side actions
    // (mute, disconnect) already notify from within the daemon itself
    // (consistent regardless of what triggers them); this covers the one
    // action - stopping/starting the service - that isn't a D-Bus call at
    // all so the daemon has no hook to do it from.
    function notifyClient(summary, body) {
        const cmd = "notify-send -a micdroid -i audio-input-microphone "
            + shQuote(summary) + " " + shQuote(body || "")
        control.run(cmd)
    }

    function performQuickAction() {
        switch (Plasmoid.configuration.quickAction) {
        case 0: // Toggle mute
            toggleMute()
            break
        case 1: // Disconnect active wireless device
            if (!root.activeDevice) {
                notifyClient(i18n("Micdroid"), i18n("No device is currently forwarding"))
            } else if (root.activeDevice.indexOf(":") === -1) {
                notifyClient(i18n("Micdroid"), i18n("The active device is wired (USB) - nothing to disconnect"))
            } else {
                disconnectDevice(root.activeDevice)
            }
            break
        case 2: // Stop/start the backend service
            toggleService()
            break
        }
    }

    // Index order must match the ComboBox models in
    // contents/ui/config/ConfigAudio.qml.
    readonly property var audioSourceValues: [
        "mic", "mic-voice-communication", "mic-unprocessed", "mic-camcorder", "mic-voice-recognition"
    ]
    readonly property var audioCodecValues: ["raw", "opus", "aac", "flac"]

    function pushConfig() {
        const backoff = String(Plasmoid.configuration.reconnectBackoffSec)
            .split(",").map(s => parseInt(s.trim(), 10)).filter(n => !isNaN(n))
        const cfg = {
            audioSource: audioSourceValues[Plasmoid.configuration.audioSource] || "mic",
            audioCodec: audioCodecValues[Plasmoid.configuration.audioCodec] || "raw",
            virtualSinkName: Plasmoid.configuration.virtualSinkName,
            virtualSourceName: Plasmoid.configuration.virtualSourceName,
            autoStartOnKnownDevice: Plasmoid.configuration.autoStartOnKnownDevice,
            probeIntervalSec: Plasmoid.configuration.probeIntervalSec,
            maxReconnectAttempts: Plasmoid.configuration.maxReconnectAttempts,
            reconnectBackoffSec: backoff.length ? backoff : [2, 5, 10, 20, 40, 60],
            adbPath: Plasmoid.configuration.adbPath,
            scrcpyPath: Plasmoid.configuration.scrcpyPath,
        }
        control.run(codePath("daemonctl.sh") + " SetConfig " + shQuote(configToGVariant(cfg)))
    }

    // --- bootstrap ---------------------------------------------------

    function bootstrap() {
        control.run(codePath("servicectl.sh") + " ensure-running", function (ok) {
            root.serviceRunning = ok
            if (!ok) return
            pushConfig()
            refreshDevices()
            refreshStatus()
            refreshMuteState()
            eventStream.arm()
        })
    }

    Component.onCompleted: Qt.callLater(bootstrap)

    // Plasmoid has no "configurationChanged" signal (confirmed via a QML
    // warning during testing) - push settings once the config dialog closes
    // instead, via the real userConfiguring property.
    Connections {
        target: Plasmoid
        function onUserConfiguringChanged() {
            if (!Plasmoid.userConfiguring) root.pushConfig()
        }
    }

    compactRepresentation: Views.CompactView {
        dependenciesOk: root.dependenciesOk
        serviceRunning: root.serviceRunning
        forwardingState: root.forwardingState
        onClicked: root.expanded = !root.expanded
        onMiddleClicked: root.performQuickAction()
    }

    fullRepresentation: Views.MicdroidPopup {
        micdroid: root
    }
}
