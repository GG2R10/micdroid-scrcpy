import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Audio")
        icon: "audio-input-microphone"
        source: "config/ConfigAudio.qml"
    }
    ConfigCategory {
        name: i18n("Visuals / Performance")
        icon: "preferences-desktop-theme"
        source: "config/ConfigVisuals.qml"
    }
    ConfigCategory {
        name: i18n("Advanced")
        icon: "configure"
        source: "config/ConfigAdvanced.qml"
    }
}
