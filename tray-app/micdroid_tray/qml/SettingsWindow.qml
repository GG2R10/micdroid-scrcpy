import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Tray-app equivalent of ../../package/contents/ui/config/ConfigAudio.qml +
// ConfigAdvanced.qml, merged into one window. Much simpler than those two:
// there's no kcfg here, so none of the "every category page needs a
// placeholder cfg_X for every other page's entries" workaround applies -
// each field just binds straight to (and writes straight back to) the
// matching `bridge` property, which pushes to the daemon via SetConfig
// itself (see bridge.py's _config_set). Not symlinked from the plasmoid's
// config/ directory since the two have no code in common beyond field
// labels - kcfg's `property alias cfg_x: widget.property` pattern doesn't
// apply to a plain QObject-backed property at all.
QQC2.ApplicationWindow {
    id: window
    title: i18n("Micdroid Settings")
    width: Kirigami.Units.gridUnit * 26
    height: Kirigami.Units.gridUnit * 28

    QQC2.ScrollView {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        contentWidth: availableWidth

        Kirigami.FormLayout {
            width: parent.width

            Kirigami.Heading {
                Kirigami.FormData.isSection: true
                level: 4
                text: i18n("Audio")
            }

            QQC2.ComboBox {
                Kirigami.FormData.label: i18n("Audio source:")
                model: [
                    i18n("Microphone"),
                    i18n("Microphone (voice communication – echo cancel/AGC)"),
                    i18n("Microphone (unprocessed)"),
                    i18n("Microphone (camcorder)"),
                    i18n("Microphone (voice recognition)")
                ]
                currentIndex: bridge.audioSourceOptions.indexOf(bridge.audioSource)
                onActivated: (index) => bridge.audioSource = bridge.audioSourceOptions[index]
            }

            QQC2.ComboBox {
                Kirigami.FormData.label: i18n("Audio codec:")
                model: [
                    i18n("Raw PCM (best quality, more bandwidth)"),
                    i18n("Opus"),
                    i18n("AAC"),
                    i18n("FLAC")
                ]
                currentIndex: bridge.audioCodecOptions.indexOf(bridge.audioCodec)
                onActivated: (index) => bridge.audioCodec = bridge.audioCodecOptions[index]
            }

            QQC2.TextField {
                Kirigami.FormData.label: i18n("Virtual sink name:")
                text: bridge.virtualSinkName
                onEditingFinished: bridge.virtualSinkName = text
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Virtual source name:")
                text: bridge.virtualSourceName
                onEditingFinished: bridge.virtualSourceName = text
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Virtual sink description:")
                text: bridge.virtualSinkDescription
                placeholderText: bridge.virtualSinkName
                onEditingFinished: bridge.virtualSinkDescription = text
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Virtual source description:")
                text: bridge.virtualSourceDescription
                placeholderText: bridge.virtualSourceName
                onEditingFinished: bridge.virtualSourceDescription = text
            }
            QQC2.CheckBox {
                Kirigami.FormData.label: i18n("System default:")
                text: i18n("Set as the system's default microphone while forwarding")
                checked: bridge.setAsDefaultSource
                onToggled: bridge.setAsDefaultSource = checked
            }

            Kirigami.Separator { Kirigami.FormData.isSection: true }
            Kirigami.Heading {
                Kirigami.FormData.isSection: true
                level: 4
                text: i18n("Advanced")
            }

            QQC2.CheckBox {
                Kirigami.FormData.label: i18n("Auto-start:")
                text: i18n("Start forwarding automatically for known devices")
                checked: bridge.autoStartOnKnownDevice
                onToggled: bridge.autoStartOnKnownDevice = checked
            }
            QQC2.SpinBox {
                Kirigami.FormData.label: i18n("Liveness probe interval (seconds):")
                from: 5
                to: 120
                value: bridge.probeIntervalSec
                onValueModified: bridge.probeIntervalSec = value
            }
            QQC2.SpinBox {
                Kirigami.FormData.label: i18n("Max reconnect attempts:")
                from: 1
                to: 20
                value: bridge.maxReconnectAttempts
                onValueModified: bridge.maxReconnectAttempts = value
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Reconnect backoff (seconds, comma-separated):")
                text: bridge.reconnectBackoffSec
                onEditingFinished: bridge.reconnectBackoffSec = text
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("adb path override:")
                placeholderText: i18n("leave empty to use PATH")
                text: bridge.adbPath
                onEditingFinished: bridge.adbPath = text
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("scrcpy path override:")
                placeholderText: i18n("leave empty to use PATH")
                text: bridge.scrcpyPath
                onEditingFinished: bridge.scrcpyPath = text
            }
        }
    }
}
