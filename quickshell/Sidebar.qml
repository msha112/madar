// Madar — side rail (pinned & open apps · tray · control center · battery · clock)
// Location: ~/.config/quickshell/Sidebar.qml
//
//   click an app      → open it / switch to it / minimize it if it's already in front
//   right-click       → pin or unpin · new window · minimize · close
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

PanelWindow {
    id: root

    WlrLayershell.namespace: "madar-rail"
    anchors { left: true; top: true; bottom: true }
    // Floating normally; docks flush to the screen edge while a window is maximized
    readonly property int edge: docked ? 0 : Theme.gap
    margins { left: root.edge; top: root.edge; bottom: root.edge }
    implicitWidth: Theme.railWidth
    color: "transparent"

    signal launcherRequested()
    signal controlCenterRequested()
    property int notifCount: 0

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ── Is a window on the visible workspace filling the screen (maximized)? ──
    property bool docked: false
    Process {
        id: dockCheck
        command: ["sh", "-c", "hyprctl -j monitors; echo '@@'; hyprctl -j clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = this.text.split("@@");
                    const mon = JSON.parse(parts[0]).find(m => m.name === root.screen?.name);
                    if (!mon) return;
                    const mw = Math.floor(mon.width / mon.scale), mh = Math.floor(mon.height / mon.scale);
                    const rail = Theme.railWidth;
                    root.docked = JSON.parse(parts[1]).some(c =>
                        c.mapped && !c.hidden && c.workspace.id === mon.activeWorkspace.id
                        && (c.fullscreen === 1
                            || (Math.abs(c.at[0] - (mon.x + rail)) <= 4 && c.size[0] >= mw - rail - 4 && c.size[1] >= mh - 4)));
                } catch (e) {}
            }
        }
    }
    Timer { id: dockDelay; interval: 80; onTriggered: dockCheck.running = true }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["fullscreen", "workspace", "workspacev2", "focusedmon", "openwindow", "closewindow",
                 "movewindow", "movewindowv2", "activewindowv2", "changefloatingmode"].indexOf(event.name) >= 0)
                dockDelay.restart();
        }
    }
    // windows can also be resized or dragged without any event, so look again now and then
    Timer { interval: 1200; running: true; repeat: true; onTriggered: if (!dockCheck.running) dockCheck.running = true }
    Component.onCompleted: dockCheck.running = true

    // ── Pinned + running apps, grouped per app ───────────────
    readonly property var appGroups: {
        const groups = [];
        const byKey = {};
        for (const id of Theme.pinned) {
            const e = Windows.entryFor(id);
            const key = e ? e.id : id;
            if (byKey[key]) continue;
            const g = { key: key, entry: e, pinId: id, windows: [] };
            groups.push(g);
            byKey[key] = g;
        }
        for (const t of Hyprland.toplevels.values) {
            const aid = Windows.appId(t);
            if (aid === "") continue;
            const e = Windows.entryFor(aid);
            const key = e ? e.id : aid;
            let g = byKey[key];
            if (!g) {
                g = { key: key, entry: e, pinId: e ? e.id : aid, windows: [] };
                groups.push(g);
                byKey[key] = g;
            }
            g.windows.push(t);
        }
        return groups.filter(g => g.entry || g.windows.length > 0);
    }

    function clickGroup(g) {
        const ws = g.windows;
        if (ws.length === 0) { g.entry?.execute(); return; }
        const active = ws.find(t => Windows.isActive(t));
        if (active && ws.length === 1) { Windows.minimize(active); return; }
        if (ws.length === 1) { Windows.focus(ws[0]); return; }
        picker.openFor(g, null);
    }

    // ── Reusable pieces ──────────────────────────────────────
    component RailButton: Rectangle {
        id: btn
        property int size: 44
        property color baseColor: "transparent"
        property color hoverColor: Theme.hover
        readonly property bool hovered: mouse.containsMouse
        signal clicked()
        signal rightClicked()

        implicitWidth: size
        implicitHeight: size
        radius: size * 0.32
        color: mouse.containsMouse ? hoverColor : baseColor
        scale: mouse.pressed ? 0.92 : 1.0

        Behavior on color { ColorAnimation { duration: Theme.anim } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: m => { if (m.button === Qt.RightButton) btn.rightClicked(); else btn.clicked() }
        }
    }

    component MenuItem: Rectangle {
        id: mi
        property string label: ""
        property bool danger: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 10
        color: miMouse.containsMouse ? Theme.hover : "transparent"
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: mi.label
            font.family: Theme.font; font.pixelSize: 13
            color: mi.danger ? Theme.danger : Theme.text
        }
        MouseArea {
            id: miMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mi.clicked()
        }
    }

    // ── The rail ─────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: root.docked ? 0 : Theme.radius
        color: root.docked ? Theme.bg : Theme.panel
        border.color: Theme.panelLine
        border.width: root.docked ? 0 : 1
        Behavior on radius { NumberAnimation { duration: 160 } }
        Behavior on color { ColorAnimation { duration: 160 } }

        // thin divider on the right edge while docked
        Rectangle {
            visible: root.docked
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.panelLine
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 14
            anchors.bottomMargin: 16
            spacing: 8

            // Logo → app launcher
            RailButton {
                Layout.alignment: Qt.AlignHCenter
                baseColor: Theme.accent
                hoverColor: Qt.lighter(Theme.accent, 1.1)
                onClicked: root.launcherRequested()

                Rectangle {
                    anchors.centerIn: parent
                    width: 20; height: 20; radius: 10
                    color: "transparent"
                    border.color: Theme.accentInk
                    border.width: 2.2
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 6; height: 6; radius: 3
                    color: Theme.accentInk
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                Layout.bottomMargin: 6
                implicitWidth: 28
                implicitHeight: 1
                color: Theme.divider
            }

            // Apps
            Repeater {
                model: root.appGroups

                delegate: Item {
                    id: app
                    required property var modelData
                    readonly property var group: modelData
                    readonly property int count: group.windows.length
                    readonly property bool active: group.windows.some(t => Windows.isActive(t))
                    readonly property bool allMinimized: count > 0 && group.windows.every(t => Windows.isMinimized(t))

                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Theme.railWidth
                    implicitHeight: 48

                    // running indicator on the outer edge: one bar per window (max 3)
                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Repeater {
                            model: Math.min(app.count, 3)
                            Rectangle {
                                width: 3
                                height: app.active ? 16 / Math.min(app.count, 3) + 4 : 6
                                radius: 2
                                color: app.active ? Theme.accent : Theme.muted
                                Behavior on height { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    RailButton {
                        id: appBtn
                        anchors.centerIn: parent
                        baseColor: app.active ? Theme.active : "transparent"
                        onClicked: { if (app.count > 1) picker.openFor(app.group, app); else root.clickGroup(app.group) }
                        onRightClicked: menu.openFor(app.group, app)

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 36
                            opacity: app.allMinimized ? 0.45 : 1
                            source: Quickshell.iconPath(app.group.entry?.icon ?? app.group.key, "application-x-executable")
                            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                        }
                    }

                    // name tooltip
                    PopupWindow {
                        anchor.window: root
                        anchor.rect.x: Theme.railWidth + 10
                        anchor.rect.y: app.mapToItem(null, 0, 0).y + 9
                        implicitWidth: tipText.implicitWidth + 20
                        implicitHeight: 30
                        visible: appBtn.hovered && !menu.visible && !picker.visible
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Theme.cardGlass
                            border.color: Theme.panelLine
                            Text {
                                id: tipText
                                anchors.centerIn: parent
                                text: (app.group.entry?.name ?? app.group.key) + (app.allMinimized ? "  ·  minimized" : "")
                                font.family: Theme.font; font.pixelSize: 12
                                color: Theme.text
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // System tray (apps running in the background)
            Repeater {
                model: SystemTray.items

                delegate: Item {
                    id: trayItem
                    required property var modelData
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 36
                    implicitHeight: 32

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: trayMouse.containsMouse ? Theme.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.anim } }
                    }
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 18
                        source: trayItem.modelData.icon
                    }
                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            const item = trayItem.modelData;
                            const p = trayItem.mapToItem(null, trayItem.width + 8, 0);
                            if (mouse.button === Qt.MiddleButton) item.secondaryActivate();
                            else if (mouse.button === Qt.RightButton || item.onlyMenu) {
                                if (item.hasMenu) item.display(root, p.x, p.y);
                            } else item.activate();
                        }
                    }
                }
            }

            // Keyboard language — click to switch
            RailButton {
                Layout.alignment: Qt.AlignHCenter
                size: 36
                baseColor: Theme.raised
                onClicked: Keyboard.next()
                Text {
                    anchors.centerIn: parent
                    text: Keyboard.badge
                    font.family: Keyboard.arabic ? "Noto Sans Arabic" : Theme.font
                    font.pixelSize: Keyboard.arabic ? 15 : 12
                    font.weight: Font.Bold
                    color: Theme.text
                }
            }

            // Control center (sliders icon + notification badge)
            RailButton {
                Layout.alignment: Qt.AlignHCenter
                onClicked: root.controlCenterRequested()

                Column {
                    anchors.centerIn: parent
                    spacing: 5
                    Repeater {
                        model: [0.65, 0.3, 0.8]
                        Item {
                            required property real modelData
                            width: 20; height: 4
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; radius: 1; color: Theme.sub }
                            Rectangle {
                                x: parent.width * parent.modelData - 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8; height: 8; radius: 4
                                color: Theme.text
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.notifCount > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 2
                    width: Math.max(16, badge.implicitWidth + 8); height: 16; radius: 8
                    color: Theme.accent
                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: root.notifCount > 9 ? "9+" : root.notifCount
                        font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold
                        color: Theme.accentInk
                    }
                }
            }

            // Battery ring
            Item {
                id: batt
                readonly property var dev: UPower.displayDevice
                readonly property real pct: {
                    const p = dev ? dev.percentage : 0;
                    return p > 1 ? p / 100 : p;
                }
                readonly property bool charging: dev !== null && dev.state === UPowerDeviceState.Charging
                readonly property color ringColor: charging ? "#6FB3A8"
                                                 : (pct < 0.2 ? Theme.danger : Theme.accent)

                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                implicitWidth: 40
                implicitHeight: 40

                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Theme.track
                        strokeWidth: 4
                        PathAngleArc { centerX: 20; centerY: 20; radiusX: 16; radiusY: 16; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: batt.ringColor
                        strokeWidth: 4
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 20; centerY: 20; radiusX: 16; radiusY: 16
                            startAngle: -90
                            sweepAngle: 360 * batt.pct
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: Math.round(batt.pct * 100)
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.text
                }
            }

            // Vertical clock
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: -2

                readonly property int h: clock.date.getHours()

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: String(parent.h % 12 || 12).padStart(2, "0")
                    font.family: Theme.font
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: Theme.text
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: String(clock.date.getMinutes()).padStart(2, "0")
                    font.family: Theme.font
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: Theme.accent
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    text: parent.h < 12 ? "AM" : "PM"
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: Theme.sub
                }
            }
        }
    }

    // ── Window picker: an app with several windows shows them all ──
    PopupWindow {
        id: picker
        property string key: ""
        property real yPos: 0
        // looked up live, so the list updates when a window opens or closes
        readonly property var group: root.appGroups.find(g => g.key === key) ?? null
        readonly property var wins: group ? group.windows : []
        onWinsChanged: if (visible && wins.length === 0) visible = false

        function openFor(g, item) {
            key = g.key;
            if (item) yPos = item.mapToItem(null, 0, 0).y;
            visible = true;
        }

        anchor.window: root
        anchor.rect.x: Theme.railWidth + 10
        anchor.rect.y: Math.max(0, Math.min(yPos - 60, root.height - implicitHeight))
        implicitWidth: Math.max(260, pickRow.implicitWidth + 24)
        implicitHeight: pickCol.implicitHeight + 24
        visible: false
        color: "transparent"

        HyprlandFocusGrab {
            windows: [picker]
            active: picker.visible
            onCleared: picker.visible = false
        }

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Theme.cardGlass
            border.color: Theme.panelLine
            border.width: 1

            ColumnLayout {
                id: pickCol
                anchors { left: parent.left; top: parent.top; margins: 12 }
                spacing: 10

                RowLayout {
                    Layout.leftMargin: 4
                    spacing: 8
                    Text {
                        text: (picker.group?.entry?.name ?? picker.group?.key ?? "") + "  ·  " + picker.wins.length + " windows"
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Text {
                        visible: !!picker.group?.entry
                        text: "+ New window"
                        font.family: Theme.font; font.pixelSize: 12
                        color: Theme.accent
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { picker.visible = false; picker.group.entry.execute() }
                        }
                    }
                }

                Row {
                    id: pickRow
                    spacing: 10

                    Repeater {
                        model: picker.visible ? picker.wins : []

                        delegate: Item {
                            id: pw
                            required property var modelData
                            readonly property bool minimized: Windows.isMinimized(modelData)
                            readonly property bool current: Windows.isActive(modelData)
                            width: 200
                            height: 150

                            Rectangle {
                                id: pwFrame
                                width: parent.width
                                height: 118
                                radius: 14
                                color: Theme.card
                                border.width: pwMouse.containsMouse || pw.current ? 2 : 1
                                border.color: pwMouse.containsMouse ? Theme.accent : (pw.current ? Theme.accentLine : Theme.panelLine)
                                clip: true

                                ScreencopyView {
                                    id: pwPreview
                                    anchors.centerIn: parent
                                    captureSource: picker.visible && !pw.minimized ? (pw.modelData.wayland ?? null) : null
                                    live: true
                                    constraintSize: Qt.size(pwFrame.width - 10, pwFrame.height - 10)
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !pwPreview.hasContent
                                    implicitSize: 48
                                    opacity: pw.minimized ? 0.5 : 1
                                    source: Quickshell.iconPath(picker.group?.entry?.icon ?? Windows.appId(pw.modelData), "application-x-executable")
                                }
                                Rectangle {
                                    visible: pw.minimized
                                    anchors { left: parent.left; top: parent.top; margins: 8 }
                                    implicitWidth: minLbl.implicitWidth + 12; implicitHeight: 20; radius: 6
                                    color: Theme.raised
                                    Text { id: minLbl; anchors.centerIn: parent; text: "Minimized"; font.family: Theme.font; font.pixelSize: 10; color: Theme.sub }
                                }

                                MouseArea {
                                    id: pwMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: m => {
                                        if (m.button === Qt.MiddleButton) { Windows.close(pw.modelData); return; }
                                        picker.visible = false;
                                        Windows.focus(pw.modelData);
                                    }
                                }

                                // close (on hover)
                                Rectangle {
                                    visible: pwMouse.containsMouse || closeArea.containsMouse
                                    anchors { right: parent.right; top: parent.top; margins: 6 }
                                    width: 26; height: 26; radius: 13
                                    color: closeArea.containsMouse ? Theme.danger : Theme.raised
                                    Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; rotation: 45; color: Theme.text }
                                    Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; rotation: -45; color: Theme.text }
                                    MouseArea {
                                        id: closeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Windows.close(pw.modelData)
                                    }
                                }
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: Windows.title(pw.modelData) || (picker.group?.entry?.name ?? "")
                                font.family: Theme.font; font.pixelSize: 12
                                font.weight: pw.current ? Font.DemiBold : Font.Normal
                                color: pw.current ? Theme.text : Theme.sub
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Right-click menu for an app ──────────────────────────
    PopupWindow {
        id: menu
        property var group: null
        property real yPos: 0

        function openFor(g, item) {
            group = g;
            yPos = item.mapToItem(null, 0, 0).y;
            visible = true;
        }

        anchor.window: root
        anchor.rect.x: Theme.railWidth + 10
        anchor.rect.y: yPos
        implicitWidth: 220
        implicitHeight: menuCol.implicitHeight + 12
        visible: false
        color: "transparent"

        HyprlandFocusGrab {
            windows: [menu]
            active: menu.visible
            onCleared: menu.visible = false
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.cardGlass
            border.color: Theme.panelLine
            border.width: 1

            ColumnLayout {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Text {
                    Layout.leftMargin: 12
                    Layout.topMargin: 6
                    Layout.bottomMargin: 4
                    text: menu.group?.entry?.name ?? menu.group?.key ?? ""
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: Theme.sub
                }
                MenuItem {
                    visible: !!menu.group?.entry
                    label: "New window"
                    onClicked: { menu.visible = false; menu.group.entry.execute() }
                }
                MenuItem {
                    label: Theme.isPinned(menu.group?.pinId ?? "") ? "Unpin from rail" : "Pin to rail"
                    onClicked: { menu.visible = false; Theme.togglePin(menu.group.pinId) }
                }
                MenuItem {
                    visible: (menu.group?.windows?.length ?? 0) > 0 && !menu.group.windows.every(t => Windows.isMinimized(t))
                    label: "Minimize"
                    onClicked: { menu.visible = false; menu.group.windows.forEach(t => { if (!Windows.isMinimized(t)) Windows.minimize(t) }) }
                }
                MenuItem {
                    visible: (menu.group?.windows?.length ?? 0) > 0
                    label: (menu.group?.windows?.length ?? 0) > 1 ? "Close all windows" : "Close"
                    danger: true
                    onClicked: { menu.visible = false; menu.group.windows.forEach(t => Windows.close(t)) }
                }
            }
        }
    }
}
