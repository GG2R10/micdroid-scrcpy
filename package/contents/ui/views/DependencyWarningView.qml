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
        text: i18n("Missing required tools:")
    }

    Repeater {
        model: micdroid ? Object.keys(micdroid.dependencyResults).filter(
            k => micdroid.requiredTools.includes(k) && !micdroid.dependencyResults[k]
        ) : []
        delegate: QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            text: "• " + modelData
            font.bold: true
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: i18n("Install the missing package(s) and rescan.")
    }

    QQC2.Button {
        Layout.alignment: Qt.AlignHCenter
        text: i18n("Rescan")
        icon.name: "view-refresh"
        onClicked: micdroid.rescanDependencies()
    }
}
