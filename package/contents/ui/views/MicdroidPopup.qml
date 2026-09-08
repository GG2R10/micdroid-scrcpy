import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: popup
    property var micdroid: null

    // Fixed, like the width - dynamically sizing the popup from
    // Loader.item.implicitHeight (tried first) didn't reliably grow it: the
    // ScrollView/Loader/content width chain (Loader width bound from
    // ScrollView.availableWidth, height read back from the loaded item)
    // isn't guaranteed to settle before the popup uses it, and in practice
    // still left the pairing view's bottom button row cut off. A flat
    // constant is simple and correct; the ScrollView below is still there
    // as a safety net for content that's genuinely taller than this (e.g.
    // a long device list).
    //
    // Both implicitWidth/Height AND Layout.preferred* are set: Plasma's
    // popup dialog sizes the fullRepresentation root by implicitWidth/
    // implicitHeight (plain Item properties), not the Layout.preferred*
    // attached properties (those only matter when this item is itself a
    // Layout's *child*, which the popup root isn't) - Layout.preferredWidth
    // alone visually "working" before was coincidental, some other default
    // happened to land close to it. implicitHeight alone previously came
    // out too small (ColumnLayout's own implicit size is the sum of its
    // children's *minimum* useful size, which for a wrapping Label can be
    // near zero) - setting it explicitly overrides that.
    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: Kirigami.Units.gridUnit * 24
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.margins: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    property bool showPairing: false
    property bool restarting: false

    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: i18n("Micdroid")
        }
        QQC2.Switch {
            id: serviceSwitch
            // Deliberately not a plain `checked: micdroid.serviceRunning`
            // binding - the same right-click quick action that can flip
            // serviceRunning while this popup is open would silently break
            // it the first time the user also touches this switch (Qt
            // detaches a declarative binding on any external/interactive
            // write to the bound property). Explicit event-driven resync
            // instead, so it stays correct regardless of what changed it.
            QQC2.ToolTip.text: checked ? i18n("Service running - click to stop") : i18n("Service stopped - click to start")
            QQC2.ToolTip.visible: hovered
            Component.onCompleted: checked = !!(micdroid && micdroid.serviceRunning)
            Connections {
                target: micdroid
                function onServiceRunningChanged() {
                    serviceSwitch.checked = micdroid.serviceRunning
                }
            }
            onToggled: {
                micdroid.toggleService(function (ok) {
                    if (!ok) serviceSwitch.checked = micdroid.serviceRunning
                })
            }
        }
        QQC2.BusyIndicator {
            visible: popup.restarting
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
        }
        QQC2.ToolButton {
            // Deliberately not `checkable: true` - QQC2's own click-driven
            // toggle would assign `checked` imperatively and permanently
            // break a declarative binding to micdroid.muted (Qt breaks a
            // binding on any external write to the bound property). The
            // icon/tooltip stay purely derived from muted instead, and
            // toggleMute() is the only thing that ever changes it.
            visible: micdroid && micdroid.serviceRunning && micdroid.dependenciesOk
            icon.name: (micdroid && micdroid.muted) ? "audio-volume-muted" : "audio-volume-high"
            QQC2.ToolTip.text: (micdroid && micdroid.muted) ? i18n("Unmute virtual microphone") : i18n("Mute virtual microphone")
            QQC2.ToolTip.visible: hovered
            onClicked: micdroid.toggleMute()
        }
        QQC2.ToolButton {
            icon.name: "view-refresh"
            enabled: !popup.restarting
            QQC2.ToolTip.text: i18n("Restart service")
            QQC2.ToolTip.visible: hovered
            onClicked: {
                popup.restarting = true
                micdroid.restartService(function () {
                    popup.restarting = false
                })
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: micdroid && micdroid.lastError.length > 0
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
        text: micdroid ? micdroid.lastError : ""
    }

    // ScrollView as a safety net: with the popup's height now fixed above
    // (see that comment), this only ever needs to kick in for content
    // that's genuinely taller than that budget (e.g. a long device list) -
    // it fills the space the fixed popup height already guarantees, rather
    // than trying to compute its own height from content.
    QQC2.ScrollView {
        id: contentScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        Loader {
            id: contentLoader
            width: contentScroll.availableWidth
            sourceComponent: {
                if (!micdroid || !micdroid.serviceRunning) return serviceUnavailableComponent
                if (!micdroid.dependenciesOk) return dependencyWarningComponent
                if (popup.showPairing) return pairingComponent
                return deviceListComponent
            }
        }
    }

    Component {
        id: serviceUnavailableComponent
        ServiceUnavailableView { micdroid: popup.micdroid }
    }
    Component {
        id: dependencyWarningComponent
        DependencyWarningView { micdroid: popup.micdroid }
    }
    Component {
        id: deviceListComponent
        DeviceListView {
            micdroid: popup.micdroid
            onPairNewDevice: popup.showPairing = true
        }
    }
    Component {
        id: pairingComponent
        PairingView {
            micdroid: popup.micdroid
            onDone: popup.showPairing = false
        }
    }
}
