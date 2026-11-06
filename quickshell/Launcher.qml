// Madar — app launcher / command line
// Location: ~/.config/quickshell/Launcher.qml
//
//   type to search apps, files (3+ letters) and the web
//   type a sum like 150*12 to calculate (Enter copies the result)
//   ">" + command runs it      ↑ ↓ move · Enter open · Esc close
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: launcher

    property bool shown: false
    property int current: 0

    function toggle() { shown ? close() : open() }
    function open()   { query.text = ""; current = 0; files = []; shown = true }
    function close()  { shown = false }

    visible: shown
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "madar-launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"

    onVisibleChanged: if (visible) query.forceActiveFocus()

    // ── Data ─────────────────────────────────────────────────
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    readonly property bool commandMode: query.text.startsWith(">")
    readonly property string command: query.text.slice(1).trim()

    // ── Calculator ───────────────────────────────────────────
    readonly property string calc: {
        const q = query.text.trim().replace(/×/g, "*").replace(/÷/g, "/").replace(/,/g, "");
        if (!/^[\d\s.+\-*\/()%^]+$/.test(q) || !/\d\s*[-+*\/%^]\s*[\d(]/.test(q)) return "";
        try {
            const v = Function('"use strict"; return (' + q.replace(/\^/g, "**") + ")")();
            if (typeof v !== "number" || !isFinite(v)) return "";
            return String(Math.round(v * 1e10) / 1e10);
        } catch (e) { return ""; }
    }

    // ── Files in your home folder (searched after a short pause) ──
    property var files: []
    Timer {
        id: fileDelay
        interval: 220
        onTriggered: {
            const q = query.text.trim();
            if (q.length < 3 || launcher.commandMode || launcher.calc !== "") { launcher.files = []; return; }
            fileProc.running = false;
            fileProc.command = ["sh", "-c",
                'find "$HOME" -maxdepth 5 \\( -path "*/.*" -o -path "*/node_modules" -o -path "*/snap" \\) -prune -o -iname "*$1*" -print 2>/dev/null | head -6',
                "sh", q];
            fileProc.running = true;
        }
    }
    Process {
        id: fileProc
        stdout: StdioCollector {
            onStreamFinished: launcher.files = this.text.split("\n").filter(l => l !== "")
        }
    }
    Connections {
        target: query
        function onTextChanged() { fileDelay.restart() }
    }

    Process { id: runner }
    function sh(cmd, arg) { runner.command = ["sh", "-c", cmd, "sh", arg]; runner.running = true }

    // ── Everything the list shows ────────────────────────────
    readonly property var results: {
        const raw = query.text.trim();
        const q = raw.toLowerCase();
        if (commandMode) return [];

        const out = [];
        if (calc !== "")
            out.push({ kind: "calc", title: "= " + calc, sub: raw + "   ·   Enter copies the result", icon: "accessories-calculator", value: calc });

        let appList = apps;
        if (q !== "") {
            const scored = [];
            for (const e of apps) {
                const name = e.name.toLowerCase();
                const extra = ((e.genericName ?? "") + " " + (e.keywords ?? []).join(" ")).toLowerCase();
                let sc = -1;
                if (name.startsWith(q)) sc = 3;
                else if (name.split(/\s+/).some(w => w.startsWith(q))) sc = 2;
                else if (name.includes(q)) sc = 1;
                else if (extra.includes(q)) sc = 0;
                if (sc >= 0) scored.push({ e: e, s: sc });
            }
            scored.sort((a, b) => (b.s - a.s) || a.e.name.localeCompare(b.e.name));
            appList = scored.map(x => x.e).slice(0, 8);
        }
        for (const e of appList)
            out.push({ kind: "app", title: e.name, sub: e.genericName || e.comment || "", icon: e.icon, entry: e });

        if (q !== "") {
            const home = Quickshell.env("HOME");
            for (const f of files) {
                const name = f.split("/").pop();
                out.push({ kind: "file", title: name, sub: f.startsWith(home) ? "~" + f.slice(home.length) : f,
                           icon: name.includes(".") ? "text-x-generic" : "folder", path: f });
            }
            if (calc === "")
                out.push({ kind: "web", title: "Search the web for “" + raw + "”", sub: "Google", icon: "web-browser", value: raw });
        }
        return out;
    }

    function launch(i) {
        if (commandMode) {
            if (command !== "") Hyprland.dispatch("exec " + command);
            close();
            return;
        }
        const it = results[i];
        if (!it) return;
        close();
        if (it.kind === "app") it.entry.execute();
        else if (it.kind === "calc") sh('printf %s "$1" | wl-copy', it.value);
        else if (it.kind === "file") sh('xdg-open "$1"', it.path);
        else if (it.kind === "web") sh('xdg-open "https://www.google.com/search?q=$(printf %s "$1" | jq -sRr @uri)"', it.value);
    }

    // ── Backdrop ─────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Theme.backdrop
        MouseArea { anchors.fill: parent; onClicked: launcher.close() }
    }

    // ── Card ─────────────────────────────────────────────────
    Rectangle {
        id: card
        width: 640
        height: content.implicitHeight + 24
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        radius: 24
        color: Theme.cardGlass
        border.color: Theme.panelLine
        border.width: 1

        opacity: 0
        scale: 0.96
        states: State {
            when: launcher.visible
            PropertyChanges { target: card; opacity: 1; scale: 1 }
        }
        transitions: Transition {
            NumberAnimation { properties: "opacity,scale"; duration: 180; easing.type: Easing.OutCubic }
        }

        // swallow clicks so they don't close the launcher
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            // Search field
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 56
                radius: 16
                color: Theme.field
                border.color: Theme.accentLine
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 12
                    spacing: 12

                    // magnifier / prompt
                    Item {
                        implicitWidth: 20; implicitHeight: 20
                        visible: !launcher.commandMode
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: "transparent"
                            border.color: Theme.sub; border.width: 2
                        }
                        Rectangle {
                            x: 12; y: 13; width: 8; height: 2.2; radius: 1
                            rotation: 45
                            color: Theme.sub
                        }
                    }
                    Text {
                        visible: launcher.commandMode
                        text: "❯"
                        font.family: Theme.font
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: Theme.accent
                    }

                    TextInput {
                        id: query
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.font
                        font.pixelSize: 17
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentInk
                        clip: true
                        focus: true

                        onTextChanged: launcher.current = 0

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: query.text === ""
                            text: "Search apps, or type > to run a command"
                            font: query.font
                            color: Theme.faint
                        }

                        Keys.onPressed: event => {
                            const last = launcher.results.length - 1;
                            if (event.key === Qt.Key_Escape) {
                                launcher.close();
                            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                launcher.current = Math.min(launcher.current + 1, last);
                            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                                launcher.current = Math.max(launcher.current - 1, 0);
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                launcher.launch(launcher.current);
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }
                    }

                    Rectangle {
                        implicitWidth: escText.implicitWidth + 14
                        implicitHeight: 24
                        radius: 6
                        color: Theme.track
                        Text {
                            id: escText
                            anchors.centerIn: parent
                            text: "Esc"
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.sub
                        }
                    }
                }
            }

            // Command preview
            Rectangle {
                visible: launcher.commandMode
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 12
                color: Theme.active
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    Text {
                        Layout.fillWidth: true
                        text: launcher.command === "" ? "Type a command…" : "Run  " + launcher.command
                        font.family: "JetBrains Mono"
                        font.pixelSize: 14
                        color: launcher.command === "" ? Theme.sub : Theme.text
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "Enter"
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.sub
                    }
                }
            }

            // Results
            ListView {
                id: list
                visible: !launcher.commandMode
                Layout.fillWidth: true
                implicitHeight: Math.min(count, 7) * 52
                model: launcher.results
                currentIndex: launcher.current
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === launcher.current

                    width: ListView.view.width
                    height: 52
                    radius: 12
                    color: selected ? Theme.active : (hover.containsMouse ? Theme.hover : "transparent")
                    Behavior on color { ColorAnimation { duration: 100 } }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: launcher.current = row.index
                        onClicked: launcher.launch(row.index)
                    }

                    // accent marker
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: row.selected ? 22 : 0
                        radius: 2
                        color: Theme.accent
                        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        IconImage {
                            implicitSize: 36
                            source: Quickshell.iconPath(row.modelData.icon ?? "", "application-x-executable")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                font.family: Theme.font
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: Theme.text
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.modelData.sub ?? ""
                                font.family: Theme.font
                                font.pixelSize: 12
                                color: Theme.sub
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: row.selected
                            text: "Enter"
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.sub
                        }
                    }
                }
            }

            // Empty state
            Text {
                visible: !launcher.commandMode && launcher.results.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                horizontalAlignment: Text.AlignHCenter
                text: "No apps match “" + query.text + "”  ·  start with > to run it as a command"
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.sub
                wrapMode: Text.WordWrap
            }

            // Footer hints
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.leftMargin: 6
                text: "↑ ↓  move     Enter  open     >  command     Esc  close"
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.faint
            }
        }
    }
}
