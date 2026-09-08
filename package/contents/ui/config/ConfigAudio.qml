import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    // Plain `property alias` bound directly to each widget's own value
    // property - this is what actually makes the config dialog's Apply
    // button react to changes (confirmed against how real KDE plasmoids like
    // org.kde.desktopcontainment's ConfigIcons.qml do it: e.g.
    // `property alias cfg_arrangement: arrangement.currentIndex`). Manually
    // re-assigning a plain `property string cfg_x` from an onActivated/
    // onTextEdited handler does NOT reliably enable Apply.
    property alias cfg_audioSource: audioSourceCombo.currentIndex
    property alias cfg_audioCodec: audioCodecCombo.currentIndex
    property alias cfg_virtualSinkName: sinkField.text
    property alias cfg_virtualSourceName: sourceField.text

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
