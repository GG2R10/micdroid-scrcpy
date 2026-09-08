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

    // --- commands -------------------------------------------------

    function startForwarding(serial) {
        control.run(codePath("daemonctl.sh") + " StartForwarding " + shQuote(serial))
    }

    function stopForwarding(serial) {
        control.run(codePath("daemonctl.sh") + " StopForwarding " + shQuote(serial))
    }

    function connectByAddress(address, onDone) {
        control.run(codePath("daemonctl.sh") + " ConnectByAddress " + shQuote(address), function (ok, stdout) {
            if (ok) refreshDevices()
            if (onDone) onDone(ok)
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

    function restartService() {
        control.run(codePath("servicectl.sh") + " restart", function (ok) {
            root.serviceRunning = ok
            if (ok) bootstrap()
        })
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
    }

    fullRepresentation: Views.MicdroidPopup {
        micdroid: root
    }
}
