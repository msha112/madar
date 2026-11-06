// Madar — one notification (used for popups and in the control center)
// Location: ~/.config/quickshell/NotificationCard.qml
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card

    required property var notif
    property bool popup: false
    signal timeout()

    readonly property bool critical: notif && notif.urgency === NotificationUrgency.Critical
    readonly property var defaultAction: notif ? notif.actions.find(a => a.identifier === "default") ?? null : null
    readonly property var buttons: notif ? notif.actions.filter(a => a.identifier !== "default") : []

    implicitHeight: body.implicitHeight + 28
    radius: 18
    color: popup ? Theme.cardGlass : (hover.containsMouse ? Theme.raised : Theme.inset)
    border.color: critical ? Theme.danger : Theme.panelLine
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }

    // Popups slide in from the right
    property real slide: popup ? 40 : 0
    transform: Translate { x: card.slide }
    opacity: popup ? 0 : 1
    Component.onCompleted: if (popup) { card.slide = 0; card.opacity = 1 }
    Behavior on slide { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 200 } }

    // Popups hide after 6 s (not while hovered, never for critical ones)
    Timer {
        interval: 6000
        running: card.popup && !card.critical && !hover.containsMouse
        onTriggered: card.timeout()
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (card.defaultAction) card.defaultAction.invoke();
            if (card.popup) card.timeout();
        }
    }

    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // App icon or attached image
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 40; implicitHeight: 40; radius: 12
            color: Theme.hover
            clip: true

            Image {
                id: img
                anchors.fill: parent
                source: card.notif?.image ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }
            IconImage {
                anchors.centerIn: parent
                implicitSize: 26
                visible: !img.visible
                source: Quickshell.iconPath(card.notif?.appIcon || card.notif?.desktopEntry || "", "dialog-information")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: card.notif?.appName || "Notification"
                    font.family: "Inter"; font.pixelSize: 11
                    color: Theme.faint
                    elide: Text.ElideRight
                }
                // close
                Rectangle {
                    implicitWidth: 22; implicitHeight: 22; radius: 11
                    color: closeMouse.containsMouse ? Theme.divider : "transparent"
                    Rectangle { anchors.centerIn: parent; width: 10; height: 1.6; radius: 1; rotation: 45; color: Theme.sub }
                    Rectangle { anchors.centerIn: parent; width: 10; height: 1.6; radius: 1; rotation: -45; color: Theme.sub }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.notif?.dismiss()
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.notif?.summary ?? ""
                font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold
                color: Theme.text
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notif?.body ?? ""
                textFormat: Text.PlainText
                font.family: "Inter"; font.pixelSize: 13
                color: Theme.sub2
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 3 : 5
                elide: Text.ElideRight
                lineHeight: 1.15
            }

            // Action buttons
            RowLayout {
                visible: card.buttons.length > 0
                Layout.topMargin: 6
                spacing: 6
                Repeater {
                    model: card.buttons
                    Rectangle {
                        id: actBtn
                        required property var modelData
                        implicitWidth: actText.implicitWidth + 24
                        implicitHeight: 30
                        radius: 10
                        color: actMouse.containsMouse ? Theme.divider : Theme.raised
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: actBtn.modelData.text
                            font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium
                            color: Theme.text
                        }
                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                actBtn.modelData.invoke();
                                if (card.popup) card.timeout();
                            }
                        }
                    }
                }
            }
        }
    }
}
