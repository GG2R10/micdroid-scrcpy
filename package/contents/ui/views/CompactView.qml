import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: compact

    property bool dependenciesOk: false
    property bool serviceRunning: false
    property string forwardingState: "Disconnected"

    function badgeColor() {
        if (!dependenciesOk || !serviceRunning) return "#9e9e9e"
        switch (forwardingState) {
        case "Forwarding": return "#2ecc71"
        case "DegradedProbing":
        case "Reconnecting": return "#f39c12"
        case "NeedsRepair": return "#e74c3c"
        default: return ""
        }
    }

    Kirigami.Icon {
        anchors.fill: parent
        source: "audio-input-microphone"
    }

    Rectangle {
        width: Math.max(6, parent.height * 0.3)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        readonly property string badge: compact.badgeColor()
        color: badge
        border.color: Qt.rgba(0, 0, 0, 0.4)
        border.width: 1
        visible: badge.length > 0
    }
}
