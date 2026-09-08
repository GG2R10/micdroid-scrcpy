import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_audioSource: "mic"
    property string cfg_audioCodec: "raw"
    property string cfg_virtualSinkName: "VirtualMicSink"
    property string cfg_virtualSourceName: "VirtualMicSource"

    QQC2.ComboBox {
        id: audioSourceCombo
        Kirigami.FormData.label: i18n("Audio source:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Microphone"), value: "mic" },
            { text: i18n("Microphone (voice communication – echo cancel/AGC)"), value: "mic-voice-communication" },
            { text: i18n("Microphone (unprocessed)"), value: "mic-unprocessed" },
            { text: i18n("Microphone (camcorder)"), value: "mic-camcorder" },
            { text: i18n("Microphone (voice recognition)"), value: "mic-voice-recognition" }
        ]
        currentIndex: indexOfValue(page.cfg_audioSource)
        onActivated: page.cfg_audioSource = currentValue
    }

    QQC2.ComboBox {
        id: audioCodecCombo
        Kirigami.FormData.label: i18n("Audio codec:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Raw PCM (best quality, more bandwidth)"), value: "raw" },
            { text: i18n("Opus"), value: "opus" },
            { text: i18n("AAC"), value: "aac" },
            { text: i18n("FLAC"), value: "flac" }
        ]
        currentIndex: indexOfValue(page.cfg_audioCodec)
        onActivated: page.cfg_audioCodec = currentValue
    }

    QQC2.TextField {
        Kirigami.FormData.label: i18n("Virtual sink name:")
        text: page.cfg_virtualSinkName
        onTextEdited: page.cfg_virtualSinkName = text
    }

    QQC2.TextField {
        Kirigami.FormData.label: i18n("Virtual source name:")
        text: page.cfg_virtualSourceName
        onTextEdited: page.cfg_virtualSourceName = text
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("If a PipeWire sink with this name already exists (for example your own loopback setup), micdroid reuses it instead of creating a new one.")
        wrapMode: Text.WordWrap
        font.italic: true
    }
}
