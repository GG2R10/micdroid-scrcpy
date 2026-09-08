import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "audio-input-microphone"
        source: "config/ConfigGeneral.qml"
    }
}
