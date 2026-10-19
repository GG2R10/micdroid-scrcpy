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
}
