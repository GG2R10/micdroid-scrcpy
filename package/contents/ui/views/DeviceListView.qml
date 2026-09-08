import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: view
    property var micdroid: null
    signal pairNewDevice()
    spacing: Kirigami.Units.smallSpacing

    readonly property var activeStates: ["Forwarding", "DegradedProbing", "Reconnecting"]

    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            Layout.fillWidth: true
            level: 5
            text: i18n("Devices")
        }
        QQC2.Button {
            text: i18n("Pair new device")
            icon.name: "list-add"
            onClicked: view.pairNewDevice()
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    QQC2.Label {
        Layout.fillWidth: true
        visible: micdroid && micdroid.devicesModel.count === 0
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: i18n("No known devices yet. Pair one above, or connect an already-paired one by address below.")
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 14)
        clip: true
        model: micdroid ? micdroid.devicesModel : null
        spacing: Kirigami.Units.smallSpacing

        delegate: Kirigami.AbstractCard {
            width: ListView.view.width

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    width: Kirigami.Units.smallSpacing * 2
                    height: width
                    radius: width / 2
                    color: {
                        if (model.forwardingState === "Forwarding") return "#2ecc71"
                        if (["DegradedProbing", "Reconnecting"].includes(model.forwardingState)) return "#f39c12"
                        if (model.forwardingState === "NeedsRepair") return "#e74c3c"
                        return model.state === "device" ? "#3498db" : "#9e9e9e"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label { text: model.name; font.bold: true; elide: Text.ElideRight }
                    QQC2.Label {
                        text: model.serial + " · " + model.forwardingState
                        opacity: 0.7
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        elide: Text.ElideRight
                    }
                }

                QQC2.Button {
                    visible: model.forwardingState === "ConnectedIdle"
                    text: i18n("Start")
                    icon.name: "media-record"
                    onClicked: micdroid.startForwarding(model.serial)
                }
                QQC2.Button {
                    visible: view.activeStates.includes(model.forwardingState)
                    text: i18n("Stop")
                    icon.name: "media-playback-stop"
                    onClicked: micdroid.stopForwarding(model.serial)
                }
                QQC2.Button {
                    // Covers both a device that dropped out entirely (its
                    // wireless adb session can end for reasons unrelated to
                    // this widget - the phone locking, Wi-Fi hiccups, or the
                    // adb *server* itself getting restarted, which drops
                    // every TCP/IP adb connection at once) and one that gave
                    // up after repeated failed reconnect attempts.
                    visible: model.forwardingState === "Disconnected" || model.forwardingState === "NeedsRepair"
                    text: i18n("Reconnect")
                    icon.name: "view-refresh"
                    onClicked: micdroid.retryDevice(model.serial)
                }
                QQC2.ToolButton {
                    icon.name: "edit-delete"
                    QQC2.ToolTip.text: i18n("Forget this device")
                    QQC2.ToolTip.visible: hovered
                    onClicked: micdroid.forgetDevice(model.serial)
                }
            }
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    RowLayout {
        Layout.fillWidth: true
        QQC2.TextField {
            id: addressField
            Layout.fillWidth: true
            placeholderText: i18n("Or connect by address (host:port)")
        }
        QQC2.Button {
            text: i18n("Connect")
            enabled: addressField.text.trim().length > 0
            onClicked: {
                micdroid.connectByAddress(addressField.text.trim(), function (ok) {
                    if (ok) addressField.text = ""
                })
            }
        }
    }
}
