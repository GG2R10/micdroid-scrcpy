import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: popup
    property var micdroid: null

    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    Layout.margins: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    property bool showPairing: false
    property bool restarting: false

    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: i18n("Micdroid")
        }
        QQC2.BusyIndicator {
            visible: popup.restarting
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
        }
        QQC2.ToolButton {
            icon.name: "view-refresh"
            enabled: !popup.restarting
            QQC2.ToolTip.text: i18n("Restart service")
            QQC2.ToolTip.visible: hovered
            onClicked: {
                popup.restarting = true
                micdroid.restartService(function () {
                    popup.restarting = false
                })
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: micdroid && micdroid.lastError.length > 0
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        text: micdroid ? micdroid.lastError : ""
    }

    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        sourceComponent: {
            if (!micdroid || !micdroid.serviceRunning) return serviceUnavailableComponent
            if (!micdroid.dependenciesOk) return dependencyWarningComponent
            if (popup.showPairing) return pairingComponent
            return deviceListComponent
        }
    }

    Component {
        id: serviceUnavailableComponent
        ServiceUnavailableView { micdroid: popup.micdroid }
    }
    Component {
        id: dependencyWarningComponent
        DependencyWarningView { micdroid: popup.micdroid }
    }
    Component {
        id: deviceListComponent
        DeviceListView {
            micdroid: popup.micdroid
            onPairNewDevice: popup.showPairing = true
        }
    }
    Component {
        id: pairingComponent
        PairingView {
            micdroid: popup.micdroid
            onDone: popup.showPairing = false
        }
    }
}
