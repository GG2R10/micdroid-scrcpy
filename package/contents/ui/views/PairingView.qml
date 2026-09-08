import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: view
    property var micdroid: null
    signal done()

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("On the phone: Settings → Developer options → Wireless debugging → \"Pair device with pairing code\". Enter what it shows below.")
        opacity: 0.8
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.TextField {
            id: hostField
            Kirigami.FormData.label: i18n("Phone IP address:")
            placeholderText: "192.168.1.42"
            inputMethodHints: Qt.ImhNoPredictiveText
        }
        QQC2.TextField {
            id: pairPortField
            Kirigami.FormData.label: i18n("Pairing port:")
            placeholderText: i18n("e.g. 39529")
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 1; top: 65535 }
        }
        QQC2.TextField {
            id: codeField
            Kirigami.FormData.label: i18n("Pairing code:")
            placeholderText: i18n("6-digit code")
            inputMethodHints: Qt.ImhDigitsOnly
            maximumLength: 6
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: text.length > 0
        color: view.lastSucceeded ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
        text: ""
        id: statusLabel
    }

    property bool lastSucceeded: false
    property bool busy: false

    RowLayout {
        Layout.fillWidth: true

        QQC2.Button {
            text: i18n("Cancel")
            onClicked: view.done()
        }

        Item { Layout.fillWidth: true }

        QQC2.Button {
            id: pairButton
            text: view.busy ? i18n("Pairing…") : i18n("Pair")
            icon.name: "network-connect"
            enabled: !view.busy
                && hostField.text.trim().length > 0
                && pairPortField.text.trim().length > 0
                && codeField.text.trim().length === 6
            onClicked: {
                view.busy = true
                statusLabel.text = ""
                view.lastSucceeded = false
                micdroid.pairDevice(hostField.text.trim(), pairPortField.text.trim(), codeField.text.trim(),
                    function (paired, connected, message) {
                        view.busy = false
                        view.lastSucceeded = paired
                        statusLabel.text = message
                        if (connected) {
                            view.done()
                        }
                    })
            }
        }
    }
}
