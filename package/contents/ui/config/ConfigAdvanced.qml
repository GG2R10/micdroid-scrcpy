import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    // See ConfigAudio.qml for why this plain `title` property is needed.
    property string title: i18n("Advanced")

    // Real, widget-backed settings for this page - see ConfigAudio.qml for
    // why plain `property alias` (not manual reassignment from a change
    // handler) is what makes Apply actually enable.
    property alias cfg_autoStartOnKnownDevice: autoStartCheck.checked
    property alias cfg_probeIntervalSec: probeSpin.value
    property alias cfg_maxReconnectAttempts: maxAttemptsSpin.value
    property alias cfg_reconnectBackoffSec: backoffField.text
    property alias cfg_adbPath: adbPathField.text
    property alias cfg_scrcpyPath: scrcpyPathField.text
    property alias cfg_quickAction: quickActionCombo.currentIndex
    property alias cfg_connectionAnimationStyle: connectionAnimationCombo.currentIndex
    readonly property bool cfg_autoStartOnKnownDeviceDefault: false
    readonly property int cfg_probeIntervalSecDefault: 15
    readonly property int cfg_maxReconnectAttemptsDefault: 5
    readonly property string cfg_reconnectBackoffSecDefault: "2,5,10,20,40,60"
    readonly property string cfg_adbPathDefault: ""
    readonly property string cfg_scrcpyPathDefault: ""
    readonly property int cfg_quickActionDefault: 0
    readonly property int cfg_connectionAnimationStyleDefault: 0

    // Placeholders for the Audio page's entries - see ConfigAudio.qml's
    // comment on why every page needs every cfg_ property to exist, even
    // ones it doesn't present UI for.
    property int cfg_audioSource: 0
    property int cfg_audioCodec: 0
    property string cfg_virtualSinkName: "VirtualMicSink"
    property string cfg_virtualSourceName: "VirtualMicSource"
    property string cfg_virtualSinkDescription: ""
    property string cfg_virtualSourceDescription: ""
    property bool cfg_setAsDefaultSource: true
    readonly property int cfg_audioSourceDefault: 0
    readonly property int cfg_audioCodecDefault: 0
    readonly property string cfg_virtualSinkNameDefault: "VirtualMicSink"
    readonly property string cfg_virtualSourceNameDefault: "VirtualMicSource"
    readonly property string cfg_virtualSinkDescriptionDefault: ""
    readonly property string cfg_virtualSourceDescriptionDefault: ""
    readonly property bool cfg_setAsDefaultSourceDefault: true

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

    Kirigami.Separator { Kirigami.FormData.isSection: true }

    QQC2.ComboBox {
        id: quickActionCombo
        Kirigami.FormData.label: i18n("Middle-click the panel icon:")
        // Index order must match main.qml's performQuickAction().
        model: [
            i18n("Toggle mute"),
            i18n("Disconnect active wireless device"),
            i18n("Stop/start the background service")
        ]
    }
    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Runs immediately, without opening the popup. Right-click still opens the normal \"Configure/Remove\" menu.")
        wrapMode: Text.WordWrap
        font.italic: true
    }

    QQC2.ComboBox {
        id: connectionAnimationCombo
        Kirigami.FormData.label: i18n("Active connection animation:")
        // Index order must match CompactView.qml's connectionAnimationStyle.
        model: [
            i18n("Rotating arc"),
            i18n("Breathing ring"),
            i18n("Double comet")
        ]
    }
}
