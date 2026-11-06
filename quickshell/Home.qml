// Madar — home screen ("Lowha")
// Shows on an empty workspace and fades away as soon as a window opens.
// Location: ~/.config/quickshell/Home.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

PanelWindow {
    id: home

    signal launcherRequested()

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "madar-home"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0                      // stays clear of the side rail
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"

    // ── State ────────────────────────────────────────────────
    readonly property var workspace: Hyprland.monitorFor(screen)?.activeWorkspace ?? null
    readonly property bool hasWindows: (workspace?.toplevels?.values?.length ?? 0) > 0
    readonly property bool active: !hasWindows

    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property int hour: clock.date.getHours()
    readonly property int minute: clock.date.getMinutes()
    readonly property string greeting: hour < 5 ? "Good night"
                                     : hour < 12 ? "Good morning"
                                     : hour < 18 ? "Good afternoon" : "Good evening"
    readonly property real dayProgress: (hour * 60 + minute) / 1440
    readonly property bool isDay: hour >= 6 && hour < 18

    // ── Weather (wttr.in, refreshed every 30 min) ────────────
    property string wxTemp: "--°"
    property string wxText: "Loading weather…"
    property string wxPlace: ""

    Process {
        id: wxProc
        command: ["curl", "-sf", "--max-time", "8", "wttr.in/" + encodeURIComponent(Theme.city) + "?format=%t|%C|%l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split("|");
                if (parts.length >= 3) {
                    home.wxTemp = parts[0].replace("+", "").replace("C", "").replace("F", "");
                    home.wxText = parts[1];
                    home.wxPlace = parts[2].split(",")[0];
                } else {
                    home.wxText = "Weather unavailable";
                }
            }
        }
    }
    Connections {
        target: Theme
        function onCityChanged() { wxProc.running = true }
    }
    Timer {
        interval: 30 * 60 * 1000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: wxProc.running = true
    }

    // ── System stats (only polled while home is visible) ─────
    property real cpu: 0
    property real ram: 0
    property real disk: 0
    property string ramText: ""
    property string diskText: ""
    property var lastCpu: null

    Process {
        id: statProc
        command: ["sh", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; df -P / | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                if (lines.length < 4) return;

                const c = lines[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = c[3] + (c[4] || 0);
                const total = c.reduce((a, b) => a + b, 0);
                if (home.lastCpu) {
                    const dt = total - home.lastCpu.total;
                    const di = idle - home.lastCpu.idle;
                    if (dt > 0) home.cpu = Math.max(0, Math.min(1, 1 - di / dt));
                }
                home.lastCpu = { total: total, idle: idle };

                const memTotal = Number(lines[1].split(/\s+/)[1]);
                const memAvail = Number(lines[2].split(/\s+/)[1]);
                home.ram = (memTotal - memAvail) / memTotal;
                home.ramText = ((memTotal - memAvail) / 1048576).toFixed(1) + " / " + Math.round(memTotal / 1048576) + " GB";

                const d = lines[3].trim().split(/\s+/);
                const dTotal = Number(d[1]), dUsed = Number(d[2]);
                home.disk = dUsed / dTotal;
                home.diskText = Math.round(dUsed / 1048576) + " / " + Math.round(dTotal / 1048576) + " GB";
            }
        }
    }
    Timer {
        interval: 3000
        running: home.active; repeat: true; triggeredOnStart: true
        onTriggered: statProc.running = true
    }

    // ── Media ────────────────────────────────────────────────
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    // ── Pinned apps ──────────────────────────────────────────
    // Same apps as the ones pinned to the side rail (right-click an icon there to pin)
    readonly property var pinned: Theme.pinned
        .map(id => Windows.entryFor(id))
        .filter(e => e)
        .slice(0, 6)

    // ── Power actions (click twice to confirm) ───────────────
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: home.armed = "" }
    function power(action, cmd) {
        if (armed !== action) { armed = action; disarm.restart(); return; }
        armed = "";
        Hyprland.dispatch(cmd);
    }

    // ── Calendar ─────────────────────────────────────────────
    readonly property var monthCells: {
        const now = clock.date;
        const y = now.getFullYear(), m = now.getMonth();
        const first = new Date(y, m, 1).getDay();          // Sunday = 0
        const days = new Date(y, m + 1, 0).getDate();
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = i - first + 1;
            cells.push({ day: d, inMonth: d >= 1 && d <= days, today: d === now.getDate() });
        }
        return cells;
    }

    // ── Layout helpers ───────────────────────────────────────
    component Tile: Rectangle {
        property var g
        property int col: 0
        property int row: 0
        property int colSpan: 1
        property int rowSpan: 1
        x: g.cellX(col)
        y: g.cellY(row)
        width: g.spanW(colSpan)
        height: g.spanH(row, rowSpan)
        radius: 28
        color: Theme.card
        border.color: Theme.panelLine
        border.width: 1
    }

    component Label: Text {
        font.family: "Inter"
        color: Theme.text
    }

    component Bar: Item {
        property real value: 0
        property color barColor: Theme.accent
        implicitHeight: 6
        Rectangle { anchors.fill: parent; radius: 3; color: Theme.track }
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: 3
            color: parent.barColor
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    component PillButton: Rectangle {
        id: pb
        property string label: ""
        property bool warn: false
        signal clicked()
        implicitHeight: 44
        radius: 14
        color: warn ? Theme.danger : (pbMouse.containsMouse ? Theme.active : Theme.raised)
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            anchors.centerIn: parent
            text: pb.label
            font.family: "Inter"
            font.pixelSize: 13
            font.weight: Font.Medium
            color: pb.warn ? Theme.accentInk : Theme.text
        }
        MouseArea {
            id: pbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    // ── Content ──────────────────────────────────────────────
    Item {
        id: page
        width: Math.min(parent.width - 96, 1320)
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter

        property real shift: home.active ? 0 : 24
        Behavior on shift { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        transform: Translate { y: page.shift }

        opacity: home.active ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        // Header
        ColumnLayout {
            id: header
            x: 0
            y: Math.max(32, (page.height - 820) / 2)
            spacing: 2
            Label {
                text: Qt.formatDate(clock.date, "dddd, MMMM d")
                font.pixelSize: 16
                color: Theme.sub
            }
            Label {
                text: home.greeting
                font.pixelSize: 44
                font.weight: Font.Bold
            }
        }

        // Battery chip
        Rectangle {
            id: battChip
            anchors.right: parent.right
            anchors.bottom: header.bottom
            anchors.bottomMargin: 8
            readonly property var dev: UPower.displayDevice
            readonly property real pct: { const p = dev ? dev.percentage : 0; return p > 1 ? p / 100 : p; }
            implicitWidth: battRow.implicitWidth + 28
            implicitHeight: 40
            radius: 20
            color: Theme.card
            border.color: Theme.panelLine
            RowLayout {
                id: battRow
                anchors.centerIn: parent
                spacing: 8
                Rectangle {
                    implicitWidth: 22; implicitHeight: 11; radius: 3
                    color: "transparent"; border.color: Theme.sub2; border.width: 1.5
                    Rectangle {
                        x: 2; y: 2; height: 7; radius: 1.5
                        width: 18 * battChip.pct
                        color: Theme.accent
                    }
                }
                Label { text: Math.round(battChip.pct * 100) + "%"; font.pixelSize: 13 }
            }
        }

        // Grid
        Item {
            id: grid
            y: header.y + header.height + 28
            width: page.width
            height: 200 + 200 + 210 + 2 * gap

            readonly property int gap: 16
            readonly property var rows: [200, 200, 210]
            readonly property real cw: (width - 3 * gap) / 4
            function cellX(c) { return c * (cw + gap) }
            function cellY(r) { let y = 0; for (let i = 0; i < r; i++) y += rows[i] + gap; return y }
            function spanW(n) { return n * cw + (n - 1) * gap }
            function spanH(r, n) { let h = 0; for (let i = r; i < r + n; i++) h += rows[i]; return h + (n - 1) * gap }

            // Clock
            Tile {
                g: grid; col: 0; row: 0; colSpan: 2; rowSpan: 2
                color: Theme.deep

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: 36
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Label { text: "Right now"; font.pixelSize: 15; color: Theme.deepSub }
                    Label {
                        text: (home.hour % 12 || 12) + ":" + String(home.minute).padStart(2, "0")
                        font.pixelSize: 136
                        font.weight: Font.Light
                        font.letterSpacing: -4
                        color: Theme.deepText
                    }
                    Label {
                        text: (home.hour < 12 ? "AM" : "PM") + "  ·  " + Math.floor(home.dayProgress * 100) + "% of the day"
                        font.pixelSize: 16
                        color: Theme.deepSub
                    }
                }

                Item {
                    anchors.right: parent.right
                    anchors.rightMargin: 40
                    anchors.verticalCenter: parent.verticalCenter
                    width: 190; height: 190

                    Shape {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.samples: 4
                        ShapePath {
                            fillColor: "transparent"; strokeColor: Qt.rgba(1, 1, 1, 0.08); strokeWidth: 14
                            PathAngleArc { centerX: 95; centerY: 95; radiusX: 80; radiusY: 80; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            fillColor: "transparent"; strokeColor: Theme.accent; strokeWidth: 14
                            capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 95; centerY: 95; radiusX: 80; radiusY: 80; startAngle: -90; sweepAngle: 360 * home.dayProgress }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 92; height: 92; radius: 46
                        color: Theme.deepRaised
                        // sun by day, moon by night
                        Rectangle {
                            anchors.centerIn: parent
                            width: 36; height: 36; radius: 18
                            color: Theme.accent
                        }
                        Rectangle {
                            visible: !home.isDay
                            x: 36; y: 22
                            width: 32; height: 32; radius: 16
                            color: Theme.deepRaised
                        }
                    }
                }
            }

            // Weather
            Tile {
                g: grid; col: 2; row: 0
                color: Theme.accent
                border.width: 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    Label { text: "Weather"; font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.accentInk }
                    Item { Layout.fillHeight: true }
                    Label { text: home.wxTemp; font.pixelSize: 52; font.weight: Font.DemiBold; color: Theme.accentInk }
                    Label {
                        Layout.fillWidth: true
                        text: home.wxText + (home.wxPlace ? "  ·  " + home.wxPlace : "")
                        font.pixelSize: 13; color: Theme.accentInk
                        elide: Text.ElideRight
                    }
                }
            }

            // Media
            Tile {
                g: grid; col: 2; row: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 10

                    RowLayout {
                        spacing: 12
                        Rectangle {
                            implicitWidth: 52; implicitHeight: 52; radius: 14
                            color: Theme.hover
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: home.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                text: home.player?.trackTitle || "Nothing playing"
                                font.pixelSize: 14; font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: home.player?.trackArtist || "Play something in any app"
                                font.pixelSize: 12; color: Theme.sub
                                elide: Text.ElideRight
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        spacing: 8
                        visible: home.player !== null
                        PillButton {
                            Layout.fillWidth: true
                            label: home.player?.isPlaying ? "Pause" : "Play"
                            onClicked: home.player?.togglePlaying()
                        }
                        PillButton {
                            implicitWidth: 64
                            label: "Next"
                            onClicked: home.player?.next()
                        }
                    }
                }
            }

            // Calendar
            Tile {
                g: grid; col: 3; row: 0; rowSpan: 2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    Label {
                        text: Qt.formatDate(clock.date, "MMMM yyyy")
                        font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Grid {
                        Layout.fillWidth: true
                        columns: 7
                        rowSpacing: 4
                        readonly property real cell: (width) / 7

                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            Label {
                                required property string modelData
                                width: parent.cell; height: 26
                                text: modelData
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 11; color: Theme.faint
                            }
                        }
                        Repeater {
                            model: home.monthCells
                            Item {
                                required property var modelData
                                width: parent.cell; height: 38
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34; height: 34; radius: 17
                                    color: parent.modelData.today ? Theme.accent : "transparent"
                                }
                                Label {
                                    anchors.centerIn: parent
                                    text: parent.modelData.inMonth ? parent.modelData.day : ""
                                    font.pixelSize: 13
                                    font.weight: parent.modelData.today ? Font.Bold : Font.Normal
                                    color: parent.modelData.today ? Theme.accentInk : Theme.text
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // Pinned apps
            Tile {
                g: grid; col: 0; row: 2; colSpan: 2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Your apps"; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Label {
                            text: "All apps  →"
                            font.pixelSize: 13; color: Theme.sub
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: home.launcherRequested() }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: home.pinned
                            Rectangle {
                                id: appBtn
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 112
                                radius: 18
                                color: appMouse.containsMouse ? Theme.raised : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 60; implicitHeight: 60; radius: 20
                                        color: "transparent"
                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: 60
                                            source: Quickshell.iconPath(appBtn.modelData.icon, "application-x-executable")
                                        }
                                    }
                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.maximumWidth: appBtn.width - 12
                                        text: appBtn.modelData.name
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: appMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: appBtn.modelData.execute()
                                }
                            }
                        }
                    }
                }
            }

            // System
            Tile {
                g: grid; col: 2; row: 2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 8

                    Label { text: "System"; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Item { Layout.fillHeight: true }
                    RowLayout { Label { text: "CPU"; font.pixelSize: 13; Layout.fillWidth: true } Label { text: Math.round(home.cpu * 100) + "%"; font.pixelSize: 13; color: Theme.sub2 } }
                    Bar { Layout.fillWidth: true; value: home.cpu; barColor: Theme.accent }
                    RowLayout { Label { text: "Memory"; font.pixelSize: 13; Layout.fillWidth: true } Label { text: home.ramText; font.pixelSize: 13; color: Theme.sub2 } }
                    Bar { Layout.fillWidth: true; value: home.ram; barColor: Theme.ram }
                    RowLayout { Label { text: "Disk"; font.pixelSize: 13; Layout.fillWidth: true } Label { text: home.diskText; font.pixelSize: 13; color: Theme.sub2 } }
                    Bar { Layout.fillWidth: true; value: home.disk; barColor: Theme.disk }
                }
            }

            // Power
            Tile {
                g: grid; col: 3; row: 2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Session"; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Label {
                            visible: home.armed !== ""
                            text: "Click again to confirm"
                            font.pixelSize: 11; color: Theme.danger
                        }
                    }
                    Item { Layout.fillHeight: true }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 8; columnSpacing: 8
                        PillButton { Layout.fillWidth: true; label: "Sleep";    warn: home.armed === "sleep";    onClicked: home.power("sleep", "exec sh -c 'quickshell ipc call lock lock; sleep 1; systemctl suspend'") }
                        PillButton { Layout.fillWidth: true; label: "Log out";  warn: home.armed === "logout";   onClicked: home.power("logout", "exit") }
                        PillButton { Layout.fillWidth: true; label: "Restart";  warn: home.armed === "reboot";   onClicked: home.power("reboot", "exec systemctl reboot") }
                        PillButton { Layout.fillWidth: true; label: "Shut down"; warn: home.armed === "off";     onClicked: home.power("off", "exec systemctl poweroff") }
                    }
                }
            }
        }

        // Command bar → opens the launcher
        Rectangle {
            id: cmdBar
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.min(grid.y + grid.height + 36, page.height - height - 28)
            width: 680; height: 60
            radius: 30
            color: cmdMouse.containsMouse ? Theme.field : Theme.card
            border.color: Theme.accentLine
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 12
                spacing: 12
                Label {
                    text: "❯"
                    font.pixelSize: 18; font.weight: Font.Bold
                    color: Theme.accent
                }
                Label {
                    Layout.fillWidth: true
                    text: "Search apps or run a command…"
                    font.pixelSize: 16; color: Theme.faint
                }
                Rectangle {
                    implicitWidth: kbd.implicitWidth + 18; implicitHeight: 30; radius: 8
                    color: Theme.track
                    Label { id: kbd; anchors.centerIn: parent; text: "Super + D"; font.pixelSize: 12; color: Theme.sub }
                }
            }
            MouseArea {
                id: cmdMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: home.launcherRequested()
            }
        }
    }
}
