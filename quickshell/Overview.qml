// Madar — overview: every open window side by side, with live previews.
// Tap Super on its own (or Super + Tab) to open; click a window to jump to it.
//   ← → ↑ ↓ move · Enter open · Delete / middle-click close · Esc or Super to leave
// Location: ~/.config/quickshell/Overview.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: ov

    property bool shown: false
    property int selected: 0

    function toggle() { shown ? close() : open() }
    function open() {
        if (Hyprland.refreshToplevels) Hyprland.refreshToplevels();
        const i = wins.findIndex(t => Windows.isActive(t));
        selected = i >= 0 ? i : 0;
        shown = true;
    }
    function close() { shown = false }
    function pick(i) {
        const t = wins[i];
        close();
        if (t) Windows.focus(t);
    }

    visible: shown
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "madar-overview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"

    // Normal windows first, minimized ones at the end
    readonly property var wins: {
        const all = Hyprland.toplevels.values.filter(t => Windows.appId(t) !== "");
        return all.filter(t => !Windows.isMinimized(t)).concat(all.filter(t => Windows.isMinimized(t)));
    }

    // ── Backdrop ─────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: ov.visible ? 0.88 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: ov.close() }
    }

    // ── Keyboard ─────────────────────────────────────────────
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        onVisibleChanged: if (visible) forceActiveFocus()

        Keys.onPressed: event => {
            const n = ov.wins.length;
            const cols = grid.columns;
            if (event.key === Qt.Key_Escape) ov.close();
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) ov.selected = Math.min(ov.selected + 1, n - 1);
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) ov.selected = Math.max(ov.selected - 1, 0);
            else if (event.key === Qt.Key_Down) ov.selected = Math.min(ov.selected + cols, n - 1);
            else if (event.key === Qt.Key_Up) ov.selected = Math.max(ov.selected - cols, 0);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) ov.pick(ov.selected);
            else if (event.key === Qt.Key_Delete && ov.wins[ov.selected]) Windows.close(ov.wins[ov.selected]);
            else return;
            event.accepted = true;
        }
    }

    // ── Header ───────────────────────────────────────────────
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 48
        spacing: 4
        opacity: ov.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: ov.wins.length === 0 ? "No open windows"
                : ov.wins.length === 1 ? "1 open window" : ov.wins.length + " open windows"
            font.family: Theme.font
            font.pixelSize: 26
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Click to switch  ·  middle-click to close  ·  Esc to go back"
            font.family: Theme.font
            font.pixelSize: 13
            color: Theme.sub
        }
    }

    // ── Window grid ──────────────────────────────────────────
    Item {
        id: area
        anchors.fill: parent
        anchors.leftMargin: Theme.railWidth + Theme.gap * 2 + 40
        anchors.rightMargin: 64
        anchors.topMargin: 140
        anchors.bottomMargin: 64

        readonly property int n: Math.max(1, ov.wins.length)
        readonly property int cols: n <= 1 ? 1 : n <= 4 ? 2 : n <= 9 ? 3 : 4
        readonly property int rows: Math.ceil(n / cols)
        readonly property int gap: 28
        readonly property real labelH: 46
        // fit 16:10 previews into the available space
        readonly property real cardW: Math.min(560,
                                              (width - (cols - 1) * gap) / cols,
                                              ((height - (rows - 1) * gap) / rows - labelH) * 1.6)
        readonly property real cardH: cardW / 1.6 + labelH

        Grid {
            id: grid
            anchors.centerIn: parent
            columns: area.cols
            spacing: area.gap

            Repeater {
                model: ov.wins

                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property var win: modelData
                    readonly property bool sel: index === ov.selected
                    readonly property bool minimized: Windows.isMinimized(win)
                    readonly property var entry: Windows.entryFor(Windows.appId(win))

                    width: area.cardW
                    height: area.cardH

                    // pop-in
                    opacity: 0
                    scale: 0.92
                    Component.onCompleted: { opacity = 1; scale = 1 }
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                    Rectangle {
                        id: frame
                        width: parent.width
                        height: parent.height - area.labelH
                        radius: 18
                        color: Theme.card
                        border.width: card.sel ? 3 : 1
                        border.color: card.sel ? Theme.accent : Theme.panelLine
                        clip: true
                        scale: card.sel ? 1.03 : 1
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }

                        ScreencopyView {
                            id: preview
                            anchors.centerIn: parent
                            captureSource: ov.visible && !card.minimized ? (card.win.wayland ?? null) : null
                            live: true
                            constraintSize: Qt.size(frame.width - 16, frame.height - 16)
                            opacity: card.minimized ? 0.35 : 1
                        }

                        // fallback: big app icon (minimized or no preview yet)
                        IconImage {
                            anchors.centerIn: parent
                            visible: !preview.hasContent
                            implicitSize: Math.min(96, frame.height * 0.4)
                            source: Quickshell.iconPath(card.entry?.icon ?? Windows.appId(card.win), "application-x-executable")
                            opacity: card.minimized ? 0.6 : 1
                        }

                        Rectangle {
                            visible: card.minimized
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 12
                            implicitWidth: minText.implicitWidth + 16
                            implicitHeight: 24
                            radius: 8
                            color: Theme.raised
                            Text {
                                id: minText
                                anchors.centerIn: parent
                                text: "Minimized"
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.sub
                            }
                        }

                        // close button (on hover)
                        Rectangle {
                            visible: cardMouse.containsMouse
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            width: 30; height: 30; radius: 15
                            color: closeMouse.containsMouse ? Theme.danger : Theme.raised
                            Rectangle { anchors.centerIn: parent; width: 12; height: 2; radius: 1; rotation: 45; color: Theme.text }
                            Rectangle { anchors.centerIn: parent; width: 12; height: 2; radius: 1; rotation: -45; color: Theme.text }
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Windows.close(card.win)
                            }
                            z: 2
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: ov.selected = card.index
                            onClicked: m => {
                                if (m.button === Qt.MiddleButton) Windows.close(card.win);
                                else ov.pick(card.index);
                            }
                        }
                    }

                    // label
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: area.labelH - 8
                        spacing: 8

                        Item { Layout.fillWidth: true }
                        IconImage {
                            implicitSize: 20
                            source: Quickshell.iconPath(card.entry?.icon ?? Windows.appId(card.win), "application-x-executable")
                        }
                        Text {
                            Layout.maximumWidth: card.width - 48
                            text: Windows.title(card.win) || (card.entry?.name ?? Windows.appId(card.win))
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: card.sel ? Font.DemiBold : Font.Normal
                            color: card.sel ? Theme.text : Theme.sub
                            elide: Text.ElideRight
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
