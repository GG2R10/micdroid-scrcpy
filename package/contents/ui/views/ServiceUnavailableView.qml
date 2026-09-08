import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: view
    property var micdroid: null
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        Layout.alignment: Qt.AlignHCenter
        source: "dialog-warning"
        implicitWidth: Kirigami.Units.iconSizes.large
        implicitHeight: Kirigami.Units.iconSizes.large
    }

    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: i18n("The micdroid background service isn't running.")
    }

    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        opacity: 0.7
        visible: micdroid && micdroid.lastError.length > 0
        text: micdroid ? micdroid.lastError : ""
    }

    QQC2.Button {
        Layout.alignment: Qt.AlignHCenter
        text: i18n("Start service")
        icon.name: "system-run"
        onClicked: micdroid.bootstrap()
    }
}
