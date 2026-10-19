import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../anim" as Anim

Item {
    id: compact

    property bool dependenciesOk: false
    property bool serviceRunning: false
    property string forwardingState: "Disconnected"
    property bool muted: false
    // 0 = breathing ring, 1 = breathing dot, 2 = breathing icon (green),
    // 3 = rotating quad comet.
    // Purely cosmetic, set from Plasmoid.configuration.connectionAnimationStyle
    // in main.qml - the daemon has no notion of this at all.
    property int connectionAnimationStyle: 0
    // See anim/AnimationController.qml: 0 = static (transition only on
    // connect), 1 = continuous; fps index into AnimationOptions.fpsValues.
    property int animationMode: 0
    property int animationFps: 2

    // Only a live backend can be forwarding: with the service stopped (or deps
    // missing) the last-known state is stale, and the grey badge must not
    // share the icon with the green indicator.
    readonly property bool isForwarding: forwardingState === "Forwarding" && serviceRunning && dependenciesOk
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
        color: compact.muted ? "#e74c3c"
             : (compact.isForwarding && compact.connectionAnimationStyle === 2) ? compact.connectionColor
             : themeColor
        // Style 2 only: breathe while in continuous mode (static otherwise).
        opacity: (anim.continuous && compact.connectionAnimationStyle === 2 && !compact.muted)
                 ? 0.55 + 0.45 * anim.wave(2000) : 1
    }

    Anim.AnimationController {
        id: anim
        active: compact.isForwarding
        mode: compact.animationMode
        fpsIndex: compact.animationFps
    }

    // Connection-active indicator - visible while a forwarding session is
    // running. Four interchangeable styles (see main.qml/ConfigVisuals.qml
    // for the setting). The shapes are drawn ONCE and never change; only
    // transforms (rotation/opacity) are animated, driven by `anim` - see
    // anim/README.md for why (CPU re-tessellation + whole-panel repaints).
    // At rest (static mode, or system animations off) the comets sit centered
    // on the cardinal points and nothing runs.
    Item {
        id: activeIndicator
        anchors.fill: parent
        visible: compact.isForwarding

        // Style 3: four short arcs, 90 degrees apart - symmetric, so the
        // resting first frame looks intentional. Drawn once; only the
        // container's rotation animates.
        Item {
            id: rotor
            anchors.fill: parent
            visible: compact.connectionAnimationStyle === 3
            // Transition: one decelerating full turn ending at rest (360 ==
            // 0). Continuous: constant speed, 6 s per revolution.
            rotation: anim.continuous
                ? anim.turns(6000) * 360
                : 360 * anim.easeOut(anim.transitionProgress)

            Shape {
                anchors.fill: parent
                antialiasing: true

                component Comet: ShapePath {
                    property real from: 0
                    strokeColor: compact.connectionColor
                    strokeWidth: Math.max(1, activeIndicator.width * 0.04)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: activeIndicator.width / 2
                        centerY: activeIndicator.height / 2
                        radiusX: activeIndicator.width / 2 - activeIndicator.width * 0.08
                        radiusY: activeIndicator.height / 2 - activeIndicator.height * 0.08
                        startAngle: from - 15
                        sweepAngle: 30
                    }
                }
                Comet { from: -90 }
                Comet { from: 0 }
                Comet { from: 90 }
                Comet { from: 180 }
            }
        }

        // Styles 0 (ring) and 1 (dot): opacity only.
        // Transition: fade in. Continuous: breathe 0.25..1 every 2 s.
        readonly property real breathe: anim.continuous
            ? 0.25 + 0.75 * anim.wave(2000)
            : anim.easeOut(anim.transitionProgress)

        Rectangle {
            anchors.fill: parent
            visible: compact.connectionAnimationStyle === 0
            radius: width / 2
            color: "transparent"
            border.color: compact.connectionColor
            border.width: Math.max(1, width * 0.04)
            opacity: activeIndicator.breathe
        }

        Rectangle {
            visible: compact.connectionAnimationStyle === 1
            width: Math.max(5, parent.height * 0.24)
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.top: parent.top
            color: compact.connectionColor
            opacity: activeIndicator.breathe
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
