// Madar — notification daemon + popups (top-right corner)
// Location: ~/.config/quickshell/Notifications.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    property bool dnd: false
    property var popups: []

    readonly property var model: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length

    function dropPopup(n) { popups = popups.filter(p => p !== n) }
    function clearAll() {
        const all = server.trackedNotifications.values.slice();
        for (const n of all) n.dismiss();
        popups = [];
    }

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            n.closed.connect(() => root.dropPopup(n));
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = [n].concat(root.popups).slice(0, 4);
        }
    }

    PanelWindow {
        visible: root.popups.length > 0
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "madar-notifications"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; right: true }
        margins { top: 12; right: 12 }
        implicitWidth: 380
        implicitHeight: Math.max(1, stack.implicitHeight)
        color: "transparent"

        ColumnLayout {
            id: stack
            width: parent.width
            spacing: 10

            Repeater {
                model: root.popups
                NotificationCard {
                    required property var modelData
                    Layout.fillWidth: true
                    notif: modelData
                    popup: true
                    onTimeout: root.dropPopup(modelData)
                }
            }
        }
    }
}
