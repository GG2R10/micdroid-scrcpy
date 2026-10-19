import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../anim" as Anim

Kirigami.FormLayout {
    id: page

    // See ConfigAudio.qml for why this plain `title` property is needed.
    property string title: i18n("Visuals / Performance")

    property alias cfg_connectionAnimationStyle: styleCombo.currentIndex
    property alias cfg_animationMode: modeCombo.currentIndex
    property alias cfg_animationFps: fpsCombo.currentIndex
    readonly property int cfg_connectionAnimationStyleDefault: 0
    readonly property int cfg_animationModeDefault: 0
    readonly property int cfg_animationFpsDefault: 2

    // Placeholders for every other page's entries - see ConfigAudio.qml's
    // comment on why every page needs every cfg_ property to exist.
    property int cfg_audioSource: 0
    property int cfg_audioCodec: 1
    property int cfg_audioBufferMsWireless: 200
    property string cfg_virtualSinkName: "VirtualMicSink"
    property string cfg_virtualSourceName: "VirtualMicSource"
    property string cfg_virtualSinkDescription: ""
    property string cfg_virtualSourceDescription: ""
    property bool cfg_setAsDefaultSource: true
    property bool cfg_autoStartOnKnownDevice: false
    property int cfg_probeIntervalSec: 15
    property int cfg_maxReconnectAttempts: 5
    property string cfg_reconnectBackoffSec: "2,5,10,20,40,60"
    property string cfg_adbPath: ""
    property string cfg_scrcpyPath: ""
    property int cfg_quickAction: 0
    readonly property int cfg_audioSourceDefault: 0
    readonly property int cfg_audioCodecDefault: 1
    readonly property int cfg_audioBufferMsWirelessDefault: 200
    readonly property string cfg_virtualSinkNameDefault: "VirtualMicSink"
    readonly property string cfg_virtualSourceNameDefault: "VirtualMicSource"
    readonly property string cfg_virtualSinkDescriptionDefault: ""
    readonly property string cfg_virtualSourceDescriptionDefault: ""
    readonly property bool cfg_setAsDefaultSourceDefault: true
    readonly property bool cfg_autoStartOnKnownDeviceDefault: false
    readonly property int cfg_probeIntervalSecDefault: 15
    readonly property int cfg_maxReconnectAttemptsDefault: 5
    readonly property string cfg_reconnectBackoffSecDefault: "2,5,10,20,40,60"
    readonly property string cfg_adbPathDefault: ""
    readonly property string cfg_scrcpyPathDefault: ""
    readonly property int cfg_quickActionDefault: 0

    QQC2.ComboBox {
        id: styleCombo
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Kirigami.FormData.label: i18n("Active connection indicator:")
        // Index order must match CompactView.qml's connectionAnimationStyle.
        model: [i18n("Breathing ring"), i18n("Breathing dot"), i18n("Breathing icon (green)"), i18n("Rotating quad comet")]
    }

    QQC2.ComboBox {
        id: modeCombo
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Kirigami.FormData.label: i18n("Animation:")
        model: Anim.AnimationOptions.modeLabels
    }

    QQC2.ComboBox {
        id: fpsCombo
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Kirigami.FormData.label: i18n("Frame rate:")
        enabled: modeCombo.currentIndex === 1
        model: Anim.AnimationOptions.fpsLabels
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 25
        text: i18n("Static mode plays one short animation when a connection starts, then stays still and costs nothing. Continuous mode keeps animating; every frame repaints the whole panel (and its blur), so keep the frame rate low. Animations are disabled automatically when Plasma's animation speed is set to instant.")
        wrapMode: Text.WordWrap
        font.italic: true
    }
}
