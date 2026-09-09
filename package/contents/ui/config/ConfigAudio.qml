import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    // A plain `title` property is what the config dialog's PageRow
    // navigator actually needs from a category page (confirmed: without
    // it, opening the dialog logged "does not have a property called
    // title" followed by PageRow TypeErrors reading a null/undefined title
    // internally). Switching the root to KCM.SimpleKCM to get a `title` for
    // free was tried and made things worse ("Created graphical object was
    // not placed in the graphics scene" - that root type isn't what
    // Plasma's own category-page loader expects here) - a plain FormLayout
    // with just this one extra property is the actual fix.
    property string title: i18n("Audio")

    // Real, widget-backed settings for this page - `property alias` bound
    // directly to each widget's own value property is what makes the
    // config dialog's Apply button react to changes (confirmed against how
    // org.kde.desktopcontainment's ConfigIcons.qml does it). Manually
    // reassigning a plain `property` from onActivated/onTextEdited does not
    // reliably enable Apply.
    property alias cfg_audioSource: audioSourceCombo.currentIndex
    property alias cfg_audioCodec: audioCodecCombo.currentIndex
    property alias cfg_virtualSinkName: sinkField.text
    property alias cfg_virtualSourceName: sourceField.text
    readonly property int cfg_audioSourceDefault: 0
    readonly property int cfg_audioCodecDefault: 0
    readonly property string cfg_virtualSinkNameDefault: "VirtualMicSink"
    readonly property string cfg_virtualSourceNameDefault: "VirtualMicSource"

    // Plasma's config-dialog loader seeds every kcfg entry's cfg_X (and
    // cfg_XDefault) property onto every loaded category page, regardless of
    // which page actually presents that setting's UI - these plain
    // (non-widget) placeholders exist purely so that seeding doesn't log
    // "does not have a property called cfg_X" for the Advanced page's
    // entries. The real, editable versions live in ConfigAdvanced.qml.
    property bool cfg_autoStartOnKnownDevice: false
    property int cfg_probeIntervalSec: 15
    property int cfg_maxReconnectAttempts: 5
    property string cfg_reconnectBackoffSec: "2,5,10,20,40,60"
    property string cfg_adbPath: ""
    property string cfg_scrcpyPath: ""
    readonly property bool cfg_autoStartOnKnownDeviceDefault: false
    readonly property int cfg_probeIntervalSecDefault: 15
    readonly property int cfg_maxReconnectAttemptsDefault: 5
    readonly property string cfg_reconnectBackoffSecDefault: "2,5,10,20,40,60"
    readonly property string cfg_adbPathDefault: ""
    readonly property string cfg_scrcpyPathDefault: ""
    property int cfg_quickAction: 0
    readonly property int cfg_quickActionDefault: 0
    property int cfg_connectionAnimationStyle: 0
    readonly property int cfg_connectionAnimationStyleDefault: 0

    QQC2.ComboBox {
        id: audioSourceCombo
        Kirigami.FormData.label: i18n("Audio source:")
        // Index order must match the mapping in main.qml's pushConfig().
        model: [
            i18n("Microphone"),
            i18n("Microphone (voice communication – echo cancel/AGC)"),
            i18n("Microphone (unprocessed)"),
            i18n("Microphone (camcorder)"),
            i18n("Microphone (voice recognition)")
        ]
    }

    QQC2.ComboBox {
        id: audioCodecCombo
        Kirigami.FormData.label: i18n("Audio codec:")
        model: [
            i18n("Raw PCM (best quality, more bandwidth)"),
            i18n("Opus"),
            i18n("AAC"),
            i18n("FLAC")
        ]
    }

    QQC2.TextField {
        id: sinkField
        Kirigami.FormData.label: i18n("Virtual sink name:")
    }

    QQC2.TextField {
        id: sourceField
        Kirigami.FormData.label: i18n("Virtual source name:")
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("If a PipeWire sink with this name already exists (for example your own loopback setup), micdroid reuses it instead of creating a new one.")
        wrapMode: Text.WordWrap
        font.italic: true
    }
}
