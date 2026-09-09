import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: compact

    property bool dependenciesOk: false
    property bool serviceRunning: false
    property string forwardingState: "Disconnected"
    property bool muted: false
    // 0 = rotating arc (original), 1 = breathing full ring, 2 = double comet.
    // Purely cosmetic, set from Plasmoid.configuration.connectionAnimationStyle
    // in main.qml - the daemon has no notion of this at all.
    property int connectionAnimationStyle: 0

    readonly property bool isForwarding: forwardingState === "Forwarding"
    readonly property color connectionColor: "#2ecc71"

    // Toggling Plasmoid.expanded is handled by main.qml (the actual
    // PlasmoidItem root), not here - this file is loaded as a separate QML
    // document, and relying on the `Plasmoid` attached singleton resolving
    // correctly across that boundary was untested/ambiguous. A plain signal
    // avoids that question entirely.
    signal clicked()
    signal middleClicked()

    function badgeColor() {
        if (!dependenciesOk || !serviceRunning) return "#9e9e9e"
        switch (forwardingState) {
        case "DegradedProbing":
        case "Reconnecting": return "#f39c12"
        case "NeedsRepair": return "#e74c3c"
        // "Forwarding" is intentionally excluded - the connection-active
        // indicator below covers that state instead of the dot badge.
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
        // isMask treats it as an alpha mask and recolors it with `color`
        // below instead, the standard technique Breeze's own "symbolic"
        // panel icons use - so it stays visible and theme-correct on both
        // light and dark panels. Its 3-tone shading (fff/e3e3e3/c2c2c2) was
        // subtle enough that flattening it to one color barely changes how
        // it looks.
        isMask: true

        // Mute indicator: the icon's own tint turns red while muted - a
        // plain static color, no pulsing (tried breathing first, per
        // request simplified to just the color swap) - independent of
        // whatever the connection-active indicator below is doing (a
        // different Item, a different property) - the two need to be able
        // to run at once (you can mute while forwarding), so they're
        // deliberately on separate visual channels rather than both
        // fighting over, say, the ring's color.
        readonly property color themeColor: Kirigami.Theme.textColor
        color: compact.muted ? "#e74c3c" : themeColor
    }

    // Connection-active indicator - visible while a forwarding session is
    // running. Three interchangeable styles (see main.qml/ConfigAdvanced.qml
    // for the setting), all sharing one rotation driver so switching styles
    // never leaves an animation needlessly running in the background.
    Item {
        id: activeIndicator
        anchors.fill: parent
        visible: compact.isForwarding

        property real sweepStart: 0
        NumberAnimation on sweepStart {
            running: compact.isForwarding && compact.connectionAnimationStyle !== 1
            from: 0
            to: 360
            duration: 6000
            loops: Animation.Infinite
        }

        property real breatheOpacity: 1
        SequentialAnimation on breatheOpacity {
            running: compact.isForwarding && compact.connectionAnimationStyle === 1
            loops: Animation.Infinite
            NumberAnimation { from: 0.25; to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.0; to: 0.25; duration: 1000; easing.type: Easing.InOutSine }
        }

        // Style 0 (rotating arc) and style 2 (double comet) - both are one
        // or two short arcs sweeping around the border. The second arc's
        // sweepAngle collapses to 0 (i.e. draws nothing) outside of style 2,
        // rather than being toggled via a `visible` property - ShapePath
        // isn't an Item and has no such property.
        Shape {
            anchors.fill: parent
            visible: compact.connectionAnimationStyle !== 1
            antialiasing: true

            ShapePath {
                strokeColor: compact.connectionColor
                strokeWidth: Math.max(1, activeIndicator.width * 0.04)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: activeIndicator.width / 2
                    centerY: activeIndicator.height / 2
                    radiusX: activeIndicator.width / 2 - activeIndicator.width * 0.08
                    radiusY: activeIndicator.height / 2 - activeIndicator.height * 0.08
                    startAngle: activeIndicator.sweepStart
                    sweepAngle: compact.connectionAnimationStyle === 2 ? 50 : 80
                }
            }
            ShapePath {
                strokeColor: compact.connectionColor
                strokeWidth: Math.max(1, activeIndicator.width * 0.04)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: activeIndicator.width / 2
                    centerY: activeIndicator.height / 2
                    radiusX: activeIndicator.width / 2 - activeIndicator.width * 0.08
                    radiusY: activeIndicator.height / 2 - activeIndicator.height * 0.08
                    startAngle: activeIndicator.sweepStart + 180
                    sweepAngle: compact.connectionAnimationStyle === 2 ? 50 : 0
                }
            }
        }

        // Style 1: full ring, no rotation, breathing opacity instead.
        Rectangle {
            anchors.fill: parent
            visible: compact.connectionAnimationStyle === 1
            radius: width / 2
            color: "transparent"
            border.color: compact.connectionColor
            border.width: Math.max(1, width * 0.04)
            opacity: activeIndicator.breatheOpacity
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
    // nothing. Middle-click is repurposed for a configurable quick action
    // (mute/disconnect/toggle service - see performQuickAction() in
    // main.qml). Right-click is deliberately NOT accepted here (first
    // tried that, then found it silently ate the standard applet context
    // menu - "Configure.../Remove" - since a MouseArea that accepts a
    // button consumes it before Plasma's own right-click handling ever
    // sees it) so the panel's normal right-click menu keeps working.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                compact.middleClicked()
            } else {
                compact.clicked()
            }
        }
    }
}
