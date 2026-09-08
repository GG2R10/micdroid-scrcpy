import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Audio")
        icon: "audio-input-microphone"
        source: "config/ConfigAudio.qml"
    }
    ConfigCategory {
        name: i18n("Advanced")
        icon: "configure"
        source: "config/ConfigAdvanced.qml"
    }
}
