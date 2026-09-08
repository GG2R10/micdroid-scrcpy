import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property bool cfg_autoStartOnKnownDevice: false
    property int cfg_probeIntervalSec: 15
    property int cfg_maxReconnectAttempts: 5
    property string cfg_reconnectBackoffSec: "2,5,10,20,40,60"
    property string cfg_adbPath: ""
    property string cfg_scrcpyPath: ""

    QQC2.CheckBox {
        Kirigami.FormData.label: i18n("Auto-start:")
        text: i18n("Start forwarding automatically for known devices")
        checked: page.cfg_autoStartOnKnownDevice
        onToggled: page.cfg_autoStartOnKnownDevice = checked
    }
    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Applies to any already-paired device that becomes reachable, subject to the one-active-session-at-a-time limit. Off by default so the microphone never activates without you asking.")
        wrapMode: Text.WordWrap
        font.italic: true
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: i18n("Liveness probe interval (seconds):")
        from: 5
        to: 120
        value: page.cfg_probeIntervalSec
        onValueModified: page.cfg_probeIntervalSec = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: i18n("Max reconnect attempts:")
        from: 1
        to: 20
        value: page.cfg_maxReconnectAttempts
        onValueModified: page.cfg_maxReconnectAttempts = value
    }

    QQC2.TextField {
        Kirigami.FormData.label: i18n("Reconnect backoff (seconds, comma-separated):")
        text: page.cfg_reconnectBackoffSec
        onTextEdited: page.cfg_reconnectBackoffSec = text
    }

    QQC2.TextField {
        Kirigami.FormData.label: i18n("adb path override:")
        placeholderText: i18n("leave empty to use PATH")
        text: page.cfg_adbPath
        onTextEdited: page.cfg_adbPath = text
    }

    QQC2.TextField {
        Kirigami.FormData.label: i18n("scrcpy path override:")
        placeholderText: i18n("leave empty to use PATH")
        text: page.cfg_scrcpyPath
        onTextEdited: page.cfg_scrcpyPath = text
    }
}
