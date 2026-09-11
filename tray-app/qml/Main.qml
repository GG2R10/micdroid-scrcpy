import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "views" as Views

// The tray app's equivalent of ../../package/contents/ui/main.qml's
// PlasmoidItem root - but far simpler, since there's no
// compactRepresentation/fullRepresentation split, no Plasmoid.configuration,
// and no Plasma5Support.DataSource shell-exec plumbing to own here: `bridge`
// (a DaemonBridge instance, set as this engine's root context property from
// main.py) already does all of that internally over real QtDBus. This file
// just hosts the same MicdroidPopup content the plasmoid's popup uses,
// unmodified, in a normal window instead of a Plasma popup dialog.
QQC2.ApplicationWindow {
    id: window
    title: i18n("Micdroid")
    width: popup.implicitWidth + 2 * Kirigami.Units.largeSpacing
    height: popup.implicitHeight + 2 * Kirigami.Units.largeSpacing
    minimumWidth: width
    minimumHeight: height

    // Steam/Discord-style tray behaviour: closing the window (the [x]
    // button, Alt+F4...) hides it instead of quitting - main.py's tray
    // icon is the only thing that actually calls Qt.quit(). Without this,
    // there would be no way to get the window back short of relaunching
    // the whole app, defeating the point of having a tray icon at all.
    onClosing: (close) => {
        close.accepted = false
        window.hide()
    }

    Component.onCompleted: bridge.bootstrap()

    Views.MicdroidPopup {
        id: popup
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        micdroid: bridge
    }
}
