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
    height: popup.implicitHeight + 2 * Kirigami.Units.largeSpacing + settingsBar.height
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

    // Reaching Settings (and fully quitting) each need their own entry
    // point here, unlike the plasmoid: Plasma gives every widget a
    // "Configure.../Remove" item on its own right-click menu for free, but
    // a standalone window inherits nothing like that. main.py's tray icon
    // *does* also have "Configuración..."/"Salir" menu items calling these
    // same two signals, but that convention (right-click the tray icon)
    // is easy to miss if you don't already know it - confirmed exactly
    // that live: the user found no obvious way to reach either one before
    // this bar existed, including no obvious way to fully quit rather
    // than just hide the window with the [x] button above.
    header: QQC2.ToolBar {
        id: settingsBar
        RowLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true }
            QQC2.ToolButton {
                icon.name: "configure"
                text: i18n("Settings")
                display: QQC2.ToolButton.IconOnly
                QQC2.ToolTip.text: i18n("Settings")
                QQC2.ToolTip.visible: hovered
                onClicked: window.openSettings()
            }
            QQC2.ToolButton {
                icon.name: "application-exit"
                text: i18n("Quit")
                display: QQC2.ToolButton.IconOnly
                QQC2.ToolTip.text: i18n("Quit Micdroid (also stops the background service)")
                QQC2.ToolTip.visible: hovered
                onClicked: window.quitRequested()
            }
        }
    }

    // main.py connects both of these directly to its own _show_settings()/
    // _quit() (see TrayApp.__init__) - the tray menu's "Configuración..."/
    // "Salir" actions call those same two Python methods too, so there's
    // only one place that owns each one's actual behaviour (e.g. _quit()
    // stopping the daemon service before exiting), regardless of which of
    // the two entry points (these buttons, or the tray menu) fired.
    signal openSettings()
    signal quitRequested()

    Component.onCompleted: bridge.bootstrap()

    Views.MicdroidPopup {
        id: popup
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        micdroid: bridge
    }
}
