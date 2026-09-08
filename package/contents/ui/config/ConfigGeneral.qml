import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// Root is KCM.SimpleKCM (not a bare Kirigami.FormLayout) to match what real
// KDE plasmoid config pages use (e.g. org.kde.desktopcontainment's
// ConfigIcons.qml) - a bare FormLayout root doesn't provide the `title`
// property and Page semantics the config dialog's PageRow navigator expects,
// which surfaced as "does not have a property called title" plus PageRow
// TypeErrors in the log until this was fixed.
KCM.SimpleKCM {
    id: page

    // Plain `property alias` bound directly to each widget's own value
    // property - this is what actually makes the config dialog's Apply
    // button react to changes (confirmed against how real KDE plasmoids like
    // org.kde.desktopcontainment's ConfigIcons.qml do it: e.g.
    // `property alias cfg_arrangement: arrangement.currentIndex`). Manually
    // re-assigning a plain `property string cfg_x` from an onActivated/
    // onTextEdited handler does NOT reliably enable Apply.
    //
    // Everything lives on a single page/category rather than being split
    // across Audio/Advanced tabs: Plasma's config-dialog loader seeds every
    // kcfg entry's cfg_X property onto EVERY loaded category page, and logs
    // "does not have a property called cfg_X" for whichever ones a given
    // page doesn't declare. Splitting into multiple categories that only
    // each own a subset of entries made that noise unavoidable; a single
    // page sidesteps it since every cfg_ property always exists here.
    property alias cfg_audioSource: audioSourceCombo.currentIndex
    property alias cfg_audioCodec: audioCodecCombo.currentIndex
    property alias cfg_virtualSinkName: sinkField.text
    property alias cfg_virtualSourceName: sourceField.text
    property alias cfg_autoStartOnKnownDevice: autoStartCheck.checked
    property alias cfg_probeIntervalSec: probeSpin.value
    property alias cfg_maxReconnectAttempts: maxAttemptsSpin.value
    property alias cfg_reconnectBackoffSec: backoffField.text
    property alias cfg_adbPath: adbPathField.text
    property alias cfg_scrcpyPath: scrcpyPathField.text

    Kirigami.FormLayout {
        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            level: 4
            text: i18n("Audio")
        }

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

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            level: 4
            text: i18n("Advanced")
        }

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
}
