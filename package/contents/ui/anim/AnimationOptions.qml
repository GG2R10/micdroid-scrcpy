pragma Singleton
import QtQuick

// Shared option lists so every widget's config page and the controller agree
// on indices. Index order is stored in kcfg (Int) - never reorder.
QtObject {
    // 0 = native refresh rate. Index 2 (30 fps) is the default.
    readonly property var fpsValues: [12, 24, 30, 60, 0]
    readonly property var fpsLabels: [
        qsTr("12 fps (lowest cost)"), qsTr("24 fps"), qsTr("30 fps (recommended)"),
        qsTr("60 fps"), qsTr("Native refresh rate (highest cost)")
    ]
    readonly property var modeLabels: [
        qsTr("Static (animate on changes only)"),
        qsTr("Continuous while active")
    ]

    // Hover/press feedback presets for HoverFeedback.qml. Index order is
    // stored in kcfg (Int) - never reorder, only append.
    //   hoverScale/pressScale : target scale while hovered / pressed
    //   overshoot             : OutBack bounce (0 = plain ease-out)
    //   hoverMs/pressMs       : duration entering hover / press
    //   pill                  : show the highlight pill behind the icon
    //   wiggle                : degrees of a one-shot tilt when hover starts
    readonly property var hoverPresets: [
        { hoverScale: 1.12, pressScale: 0.90, overshoot: 1.8, hoverMs: 220, pressMs: 80,  pill: true,  wiggle: 0 },  // Pop
        { hoverScale: 1.0,  pressScale: 1.0,  overshoot: 0,   hoverMs: 150, pressMs: 80,  pill: true,  wiggle: 0 },  // Soft
        { hoverScale: 1.08, pressScale: 0.95, overshoot: 0,   hoverMs: 160, pressMs: 80,  pill: true,  wiggle: 0 },  // Lift
        { hoverScale: 1.05, pressScale: 0.95, overshoot: 0,   hoverMs: 160, pressMs: 80,  pill: false, wiggle: 8 },  // Wiggle
        { hoverScale: 1.0,  pressScale: 1.0,  overshoot: 0,   hoverMs: 0,   pressMs: 0,   pill: false, wiggle: 0 }   // None
    ]
    readonly property var hoverStyleLabels: [
        qsTr("Pop (scale + highlight)"), qsTr("Soft (highlight only)"),
        qsTr("Lift (gentle scale)"), qsTr("Wiggle (tilt)"), qsTr("None")
    ]
}
