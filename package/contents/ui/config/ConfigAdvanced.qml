import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    // See ConfigAudio.qml for why these are plain `property alias` bound
    // directly to each widget's value property, rather than manually
    // reassigned from a change handler.
    property alias cfg_autoStartOnKnownDevice: autoStartCheck.checked
    property alias cfg_probeIntervalSec: probeSpin.value
    property alias cfg_maxReconnectAttempts: maxAttemptsSpin.value
    property alias cfg_reconnectBackoffSec: backoffField.text
    property alias cfg_adbPath: adbPathField.text
    property alias cfg_scrcpyPath: scrcpyPathField.text

    QQC2.CheckBox {
        id: autoStartCheck
        Kirigami.FormData.label: i18n("Auto-start:")
        text: i18n("Start forwarding automatically for known devices")
    }
    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Applies to any already-paired device that becomes reachable, subject to the one-active-session-at-a-time limit. Off by default so the microphone never activates without you asking.")
        wrapMode: Text.WordWrap
        font.italic: true
    }

    QQC2.SpinBox {
        id: probeSpin
        Kirigami.FormData.label: i18n("Liveness probe interval (seconds):")
        from: 5
        to: 120
    }

    QQC2.SpinBox {
        id: maxAttemptsSpin
        Kirigami.FormData.label: i18n("Max reconnect attempts:")
        from: 1
        to: 20
    }

    QQC2.TextField {
        id: backoffField
        Kirigami.FormData.label: i18n("Reconnect backoff (seconds, comma-separated):")
    }

    QQC2.TextField {
        id: adbPathField
        Kirigami.FormData.label: i18n("adb path override:")
        placeholderText: i18n("leave empty to use PATH")
    }

    QQC2.TextField {
        id: scrcpyPathField
        Kirigami.FormData.label: i18n("scrcpy path override:")
        placeholderText: i18n("leave empty to use PATH")
    }
}
