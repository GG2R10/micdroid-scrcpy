import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: compact

    property bool dependenciesOk: false
    property bool serviceRunning: false
    property string forwardingState: "Disconnected"

    readonly property bool isForwarding: forwardingState === "Forwarding"

    // Toggling Plasmoid.expanded is handled by main.qml (the actual
    // PlasmoidItem root), not here - this file is loaded as a separate QML
    // document, and relying on the `Plasmoid` attached singleton resolving
    // correctly across that boundary was untested/ambiguous. A plain signal
    // avoids that question entirely.
    signal clicked()

    function badgeColor() {
        if (!dependenciesOk || !serviceRunning) return "#9e9e9e"
        switch (forwardingState) {
        case "DegradedProbing":
        case "Reconnecting": return "#f39c12"
        case "NeedsRepair": return "#e74c3c"
        // "Forwarding" is intentionally excluded - the rotating ring below
        // is the active indicator for that state instead of the dot badge.
        default: return ""
        }
    }

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        anchors.margins: Math.max(1, Math.round(parent.width * 0.1))
        source: Qt.resolvedUrl("../../icons/micdroid.svg")
        // The source SVG is solid white/near-white - invisible on a light
        // panel theme (confirmed by rendering it on a white background).
        // isMask treats it as an alpha mask and recolors it with the
        // current theme's text color instead, the standard technique
        // Breeze's own "symbolic" panel icons use - so it stays visible and
        // theme-correct on both light and dark panels. Its 3-tone shading
        // (fff/e3e3e3/c2c2c2) was subtle enough that flattening it to one
        // color barely changes how it looks.
        isMask: true
    }

    // "Recording" ring: a short green arc that continuously sweeps around
    // the icon's circular border while a forwarding session is active -
    // the visual "activated" state the user asked for.
    Shape {
        id: activeRing
        anchors.fill: parent
        visible: compact.isForwarding
        antialiasing: true

        property real sweepStart: 0

        NumberAnimation on sweepStart {
            running: compact.isForwarding
            from: 0
            to: 360
            duration: 6000 // ~30% of the original 1800ms speed
            loops: Animation.Infinite
        }

        ShapePath {
            strokeColor: "#2ecc71"
            strokeWidth: Math.max(1, activeRing.width * 0.04) // half of the original 2 / 0.08
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: activeRing.width / 2
                centerY: activeRing.height / 2
                radiusX: activeRing.width / 2 - activeRing.width * 0.08
                radiusY: activeRing.height / 2 - activeRing.height * 0.08
                startAngle: activeRing.sweepStart
                sweepAngle: 80
            }
        }
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

    // A custom compactRepresentation replaces PlasmoidItem's default
    // click-to-expand handling entirely - without this, left-click does
    // nothing.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: compact.clicked()
    }
}
