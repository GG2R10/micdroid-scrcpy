import QtQuick
import org.kde.kirigami as Kirigami

// Reusable hover/press feedback for panel icons: a highlight "pill" behind
// the icon plus a scale (and optional one-shot tilt) the icon binds to.
// Style is a preset index (AnimationOptions.hoverPresets). Everything here is
// finite - a few hundred ms per interaction, nothing runs at rest - and only
// scale/rotation/opacity are animated.
//
// USAGE: declare it BEFORE the icon (so its pill sits behind and its
// MouseArea sits underneath; plain Items/Icons don't swallow mouse events):
//
//   Anim.HoverFeedback {
//       id: fb
//       anchors.fill: parent
//       style: Plasmoid.configuration.hoverStyle
//       onClicked: root.expanded = !root.expanded
//   }
//   Item { scale: fb.scaleFactor; rotation: fb.tilt }   // the icon
//
// If the widget already owns a MouseArea, set `useMouseArea: false` and
// drive `hovered` / `pressed` from it instead.
Item {
    id: fb

    // Index into AnimationOptions.hoverPresets.
    property int style: 0
    property bool useMouseArea: true
    property bool hovered: false
    property bool pressed: false
    // Neutral by default (follows the theme text color); override per widget.
    property color pillColor: Kirigami.Theme.textColor
    property real pillMargin: Kirigami.Units.smallSpacing * 0.5
    property real pillRadius: Kirigami.Units.cornerRadius ?? 4

    signal clicked()

    readonly property var preset: AnimationOptions.hoverPresets[Math.max(0, Math.min(style, AnimationOptions.hoverPresets.length - 1))]
    // Plasma's animation speed = instant means no motion at all.
    readonly property bool animated: Kirigami.Units.longDuration > 0

    // Outputs for the icon to bind: scale and tilt (degrees).
    property real scaleFactor: pressed ? preset.pressScale : (hovered ? preset.hoverScale : 1.0)
    property real tilt: 0

    Behavior on scaleFactor {
        NumberAnimation {
            duration: fb.animated ? (fb.pressed ? fb.preset.pressMs : fb.preset.hoverMs) : 0
            easing.type: fb.preset.overshoot > 0 ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: fb.preset.overshoot
        }
    }

    // One-shot tilt when hover starts; settles back to 0 by itself.
    SequentialAnimation {
        id: wiggle
        NumberAnimation { target: fb; property: "tilt"; to: -fb.preset.wiggle; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: fb; property: "tilt"; to: fb.preset.wiggle; duration: 140; easing.type: Easing.InOutSine }
        NumberAnimation { target: fb; property: "tilt"; to: 0; duration: 110; easing.type: Easing.InCubic }
    }
    onHoveredChanged: {
        if (hovered && animated && preset.wiggle !== 0) wiggle.restart()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: fb.pillMargin
        radius: fb.pillRadius
        color: fb.pillColor
        opacity: (fb.preset.pill && fb.hovered) ? (fb.pressed ? 0.20 : 0.12) : 0
        Behavior on opacity {
            NumberAnimation { duration: fb.animated ? 150 : 0; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: fb.useMouseArea
        hoverEnabled: true
        onEntered: fb.hovered = true
        onExited: fb.hovered = false
        onPressed: fb.pressed = true
        onReleased: fb.pressed = false
        onCanceled: fb.pressed = false
        onClicked: fb.clicked()
    }
}
